import Foundation
import Observation
import StoreKit
import LumaGridServices

/// StoreKit 2 integration. Products, prices, and names come from the App Store (or the local
/// LumaGrid.storekit file when running from Xcode). Nothing is granted until StoreKit returns a
/// verified transaction; grants go through `PurchaseProcessor`, which deduplicates consumables
/// with a durable transaction ledger. Transactions are finished only after the grant is saved.
@MainActor
@Observable
final class StoreService {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Feedback: Equatable, Identifiable {
        case purchased(productName: String)
        case pending
        case cancelled
        case failed(String)
        case restored
        case restoreFailed(String)

        var id: String {
            switch self {
            case let .purchased(name): return "purchased-\(name)"
            case .pending: return "pending"
            case .cancelled: return "cancelled"
            case let .failed(message): return "failed-\(message)"
            case .restored: return "restored"
            case let .restoreFailed(message): return "restoreFailed-\(message)"
            }
        }
    }

    private(set) var products: [String: Product] = [:]
    private(set) var loadState: LoadState = .idle
    private(set) var inFlightProductID: String?
    private(set) var isRestoring = false
    var feedback: Feedback?

    let catalog: ProductCatalog
    @ObservationIgnored private let progress: ProgressStore
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(catalog: ProductCatalog, progress: ProgressStore, isEnabled: Bool) {
        self.catalog = catalog
        self.progress = progress
        self.isEnabled = isEnabled
    }

    /// Starts listening for transactions (purchases made elsewhere, Ask to Buy approvals, refunds,
    /// renewals) and reconciles entitlements. Call once at launch.
    func start() {
        guard isEnabled, updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await processUnfinishedTransactions()
            await refreshEntitlements()
            await loadProducts()
        }
    }

    // MARK: Products

    func loadProducts() async {
        guard isEnabled else {
            loadState = .loaded
            return
        }
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: catalog.allIDs)
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func product(for id: String) -> Product? { products[id] }

    var hasAnyProducts: Bool { !products.isEmpty }

    // MARK: Purchasing

    /// Called with the result of SwiftUI's `PurchaseAction` (`@Environment(\.purchase)`), which
    /// presents Apple's purchase sheet in the right scene.
    func beginPurchase(of productID: String) -> Bool {
        guard inFlightProductID == nil, products[productID] != nil else { return false }
        inFlightProductID = productID
        return true
    }

    func completePurchase(of product: Product, result: Result<Product.PurchaseResult, Error>) async {
        defer { inFlightProductID = nil }
        switch result {
        case let .success(.success(verification)):
            let grant = await handle(verification)
            switch grant {
            case .coinsGranted, .entitlementGranted, .duplicateIgnored:
                feedback = .purchased(productName: product.displayName)
            case .rejectedUnverified:
                feedback = .failed(String(localized: "The App Store could not verify this purchase, so nothing was unlocked. Please try again later."))
            default:
                feedback = .failed(String(localized: "This purchase could not be completed."))
            }
        case .success(.pending):
            feedback = .pending
        case .success(.userCancelled):
            feedback = .cancelled
        case .success:
            feedback = .failed(String(localized: "This purchase could not be completed."))
        case let .failure(error):
            feedback = .failed(error.localizedDescription)
        }
    }

    /// Restore Purchases: syncs with the App Store, then rebuilds non-consumable entitlements.
    /// Coin balances are not restorable (they are local consumables; see README).
    func restorePurchases() async {
        guard isEnabled, !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            feedback = .restored
        } catch {
            feedback = .restoreFailed(error.localizedDescription)
        }
    }

    // MARK: Transactions

    @discardableResult
    private func handle(_ verification: VerificationResult<Transaction>) async -> PurchaseGrant {
        let snapshot = Self.snapshot(of: verification)
        // `update` saves synchronously, so the grant and ledger entry are durable before finish().
        let result = progress.update { progress in
            PurchaseProcessor.process(snapshot, catalog: catalog, progress: &progress)
        }
        if case .entitlementRevoked = result.grant {
            // A refunded theme pack can no longer stay selected.
            progress.update { $0.validateSelectedTheme(in: AppConfiguration.themes) }
        }
        if result.shouldFinishTransaction, case let .verified(transaction) = verification {
            await transaction.finish()
        }
        return result.grant
    }

    private func processUnfinishedTransactions() async {
        for await verification in Transaction.unfinished {
            await handle(verification)
        }
    }

    func refreshEntitlements() async {
        guard isEnabled else { return }
        var current: [TransactionVerification] = []
        for await verification in Transaction.currentEntitlements {
            current.append(Self.snapshot(of: verification))
        }
        progress.update { progress in
            PurchaseProcessor.reconcileEntitlements(current, catalog: catalog, progress: &progress)
            progress.validateSelectedTheme(in: AppConfiguration.themes)
        }
    }

    private static func snapshot(of verification: VerificationResult<Transaction>) -> TransactionVerification {
        switch verification {
        case let .verified(transaction):
            return .verified(TransactionSnapshot(transactionID: transaction.id, productID: transaction.productID,
                                                 isRevoked: transaction.revocationDate != nil))
        case let .unverified(transaction, _):
            return .unverified(TransactionSnapshot(transactionID: transaction.id, productID: transaction.productID,
                                                   isRevoked: transaction.revocationDate != nil))
        }
    }
}
