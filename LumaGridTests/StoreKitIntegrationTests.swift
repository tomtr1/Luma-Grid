import StoreKit
import StoreKitTest
import XCTest
import LumaGridServices
@testable import LumaGrid

/// Exercises StoreService against Xcode's local StoreKit test environment (LumaGrid.storekit).
/// Requires running on an iOS Simulator from Xcode; these do not run on Linux.
@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    private var session: SKTestSession!
    private var progress: ProgressStore!
    private var store: StoreService!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "LumaGrid")
        session.disableDialogs = true
        session.clearTransactions()
        progress = ProgressStore(repository: ProgressRepository(storage: InMemoryProgressStorage()))
        store = StoreService(catalog: AppConfiguration.productCatalog, progress: progress, isEnabled: true)
        await store.loadProducts()
    }

    func testAllConfiguredProductsLoadWithLocalizedPrices() {
        XCTAssertEqual(store.loadState, .loaded)
        for id in AppConfiguration.productCatalog.allIDs {
            let product = store.product(for: id)
            XCTAssertNotNil(product, "Missing \(id) in LumaGrid.storekit")
            XCTAssertFalse(product?.displayPrice.isEmpty ?? true)
        }
    }

    func testConsumablePurchaseGrantsCoinsOncePerTransaction() async throws {
        let id = AppConfiguration.productCatalog.identifiers.coinsSmall
        let product = try XCTUnwrap(store.product(for: id))

        XCTAssertTrue(store.beginPurchase(of: id))
        await store.completePurchase(of: product, result: .success(try await product.purchase()))
        XCTAssertEqual(progress.progress.coins, 500)
        XCTAssertEqual(progress.progress.processedTransactionIDs.count, 1)

        XCTAssertTrue(store.beginPurchase(of: id))
        await store.completePurchase(of: product, result: .success(try await product.purchase()))
        XCTAssertEqual(progress.progress.coins, 1_000)
    }

    func testRemoveForcedAdsIsGrantedAndRestorable() async throws {
        let id = AppConfiguration.productCatalog.identifiers.removeForcedAds
        let product = try XCTUnwrap(store.product(for: id))
        XCTAssertTrue(store.beginPurchase(of: id))
        await store.completePurchase(of: product, result: .success(try await product.purchase()))
        XCTAssertTrue(progress.hasRemoveForcedAds)

        // Simulate a reinstall: local cache wiped, entitlements rebuilt from StoreKit.
        progress.update { $0.purchasedProductIDs = [] }
        XCTAssertFalse(progress.hasRemoveForcedAds)
        await store.refreshEntitlements()
        XCTAssertTrue(progress.hasRemoveForcedAds)
    }

    func testFailedPurchaseGrantsNothing() async throws {
        session.failTransactionsEnabled = true
        let id = AppConfiguration.productCatalog.identifiers.coinsLarge
        let product = try XCTUnwrap(store.product(for: id))
        XCTAssertTrue(store.beginPurchase(of: id))
        do {
            let result = try await product.purchase()
            await store.completePurchase(of: product, result: .success(result))
        } catch {
            await store.completePurchase(of: product, result: .failure(error))
        }
        XCTAssertEqual(progress.progress.coins, 0)
        if case .failed = store.feedback {} else { XCTFail("Expected failure feedback, got \(String(describing: store.feedback))") }
    }

    func testAskToBuyLeavesPurchasePending() async throws {
        session.askToBuyEnabled = true
        let id = AppConfiguration.productCatalog.identifiers.themeNebula
        let product = try XCTUnwrap(store.product(for: id))
        XCTAssertTrue(store.beginPurchase(of: id))
        await store.completePurchase(of: product, result: .success(try await product.purchase()))
        XCTAssertEqual(store.feedback, .pending)
        XCTAssertFalse(progress.progress.purchasedProductIDs.contains(id))
    }
}
