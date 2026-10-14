/// Product identifiers, injected from the app's central configuration.
public struct ProductIdentifiers: Hashable, Sendable {
    public var removeForcedAds: String
    public var themeNebula: String
    public var themeSunrise: String
    public var coinsSmall: String
    public var coinsLarge: String

    public init(removeForcedAds: String, themeNebula: String, themeSunrise: String, coinsSmall: String, coinsLarge: String) {
        self.removeForcedAds = removeForcedAds
        self.themeNebula = themeNebula
        self.themeSunrise = themeSunrise
        self.coinsSmall = coinsSmall
        self.coinsLarge = coinsLarge
    }

    /// Placeholder namespace; replace before release (see APP_STORE_RELEASE_CHECKLIST.md).
    public static func placeholder(namespace: String = "com.example.lumagrid") -> ProductIdentifiers {
        ProductIdentifiers(
            removeForcedAds: "\(namespace).removeforcedads",
            themeNebula: "\(namespace).theme.nebula",
            themeSunrise: "\(namespace).theme.sunrise",
            coinsSmall: "\(namespace).coins.small",
            coinsLarge: "\(namespace).coins.large"
        )
    }
}

public enum ProductKind: Hashable, Sendable {
    case consumableCoins(amount: Int)
    case removeForcedAds
    case themePack(themeID: String)

    public var isConsumable: Bool {
        if case .consumableCoins = self { return true }
        return false
    }
}

public struct ProductDefinition: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: ProductKind
}

public struct ProductCatalog: Sendable {
    public let identifiers: ProductIdentifiers
    public let products: [ProductDefinition]

    public init(identifiers: ProductIdentifiers, smallCoinAmount: Int = 500, largeCoinAmount: Int = 1_500) {
        self.identifiers = identifiers
        self.products = [
            ProductDefinition(id: identifiers.removeForcedAds, kind: .removeForcedAds),
            ProductDefinition(id: identifiers.themeNebula, kind: .themePack(themeID: "nebula")),
            ProductDefinition(id: identifiers.themeSunrise, kind: .themePack(themeID: "sunrise")),
            ProductDefinition(id: identifiers.coinsSmall, kind: .consumableCoins(amount: smallCoinAmount)),
            ProductDefinition(id: identifiers.coinsLarge, kind: .consumableCoins(amount: largeCoinAmount)),
        ]
    }

    public var allIDs: [String] { products.map(\.id) }

    public func product(id: String) -> ProductDefinition? {
        products.first { $0.id == id }
    }
}

/// The fields of a StoreKit transaction the purchase logic needs. The app maps
/// `StoreKit.Transaction` into this so the rules can be tested without StoreKit.
public struct TransactionSnapshot: Hashable, Sendable {
    public let transactionID: UInt64
    public let productID: String
    /// Set when Apple refunded or revoked the purchase.
    public let isRevoked: Bool

    public init(transactionID: UInt64, productID: String, isRevoked: Bool = false) {
        self.transactionID = transactionID
        self.productID = productID
        self.isRevoked = isRevoked
    }
}

/// Result of StoreKit's JWS verification, mirrored from `VerificationResult`.
public enum TransactionVerification: Hashable, Sendable {
    case verified(TransactionSnapshot)
    case unverified(TransactionSnapshot)
}

public enum PurchaseGrant: Hashable, Sendable {
    case coinsGranted(Int)
    case entitlementGranted(productID: String)
    case entitlementRevoked(productID: String)
    case duplicateIgnored
    case revokedConsumableIgnored
    case rejectedUnverified
    case unknownProduct
}

public struct PurchaseProcessingResult: Hashable, Sendable {
    public let grant: PurchaseGrant
    /// Whether the app should call `transaction.finish()`. Finish only after the grant is
    /// durably saved. Unverified transactions are not finished, so they are never treated as paid.
    public let shouldFinishTransaction: Bool
}

public enum PurchaseProcessor {
    /// Applies a transaction to progress. Idempotent: replaying the same consumable transaction
    /// never grants coins twice.
    public static func process(_ verification: TransactionVerification, catalog: ProductCatalog,
                               progress: inout PlayerProgress) -> PurchaseProcessingResult {
        guard case let .verified(transaction) = verification else {
            return PurchaseProcessingResult(grant: .rejectedUnverified, shouldFinishTransaction: false)
        }
        guard let product = catalog.product(id: transaction.productID) else {
            // Not something this build sells (e.g. retired product). Finish so it stops re-delivering.
            return PurchaseProcessingResult(grant: .unknownProduct, shouldFinishTransaction: true)
        }

        switch product.kind {
        case let .consumableCoins(amount):
            let key = String(transaction.transactionID)
            if progress.processedTransactionIDs.contains(key) {
                return PurchaseProcessingResult(grant: .duplicateIgnored, shouldFinishTransaction: true)
            }
            progress.processedTransactionIDs.insert(key)
            if transaction.isRevoked {
                // A refunded consumable delivered for the first time grants nothing.
                return PurchaseProcessingResult(grant: .revokedConsumableIgnored, shouldFinishTransaction: true)
            }
            progress.addCoins(amount)
            return PurchaseProcessingResult(grant: .coinsGranted(amount), shouldFinishTransaction: true)

        case .removeForcedAds, .themePack:
            if transaction.isRevoked {
                progress.purchasedProductIDs.remove(product.id)
                return PurchaseProcessingResult(grant: .entitlementRevoked(productID: product.id), shouldFinishTransaction: true)
            }
            progress.purchasedProductIDs.insert(product.id)
            return PurchaseProcessingResult(grant: .entitlementGranted(productID: product.id), shouldFinishTransaction: true)
        }
    }

    /// Rebuilds non-consumable entitlements from StoreKit's current entitlements (used at launch
    /// and by Restore Purchases). Unverified and revoked entries are ignored. Consumable coin
    /// balances are deliberately not touched: they are not restorable through entitlements.
    public static func reconcileEntitlements(_ current: [TransactionVerification], catalog: ProductCatalog,
                                             progress: inout PlayerProgress) {
        var entitled: Set<String> = []
        for case let .verified(transaction) in current where !transaction.isRevoked {
            guard let product = catalog.product(id: transaction.productID), !product.kind.isConsumable else { continue }
            entitled.insert(product.id)
        }
        progress.purchasedProductIDs = entitled
    }

    public static func hasRemoveForcedAds(_ progress: PlayerProgress, catalog: ProductCatalog) -> Bool {
        progress.purchasedProductIDs.contains(catalog.identifiers.removeForcedAds)
    }
}
