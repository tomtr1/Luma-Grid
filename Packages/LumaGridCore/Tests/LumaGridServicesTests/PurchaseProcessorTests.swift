import XCTest
@testable import LumaGridServices

final class PurchaseProcessorTests: XCTestCase {
    private let catalog = ProductCatalog(identifiers: .placeholder())
    private var ids: ProductIdentifiers { catalog.identifiers }

    func testVerifiedConsumableGrantsCoinsOnce() {
        var progress = PlayerProgress()
        let transaction = TransactionVerification.verified(TransactionSnapshot(transactionID: 42, productID: ids.coinsSmall))

        let first = PurchaseProcessor.process(transaction, catalog: catalog, progress: &progress)
        XCTAssertEqual(first.grant, .coinsGranted(500))
        XCTAssertTrue(first.shouldFinishTransaction)
        XCTAssertEqual(progress.coins, 500)

        // StoreKit re-delivers the same transaction (e.g. app crashed before finish()).
        let duplicate = PurchaseProcessor.process(transaction, catalog: catalog, progress: &progress)
        XCTAssertEqual(duplicate.grant, .duplicateIgnored)
        XCTAssertTrue(duplicate.shouldFinishTransaction)
        XCTAssertEqual(progress.coins, 500)

        // A different transaction for the same product is a genuine second purchase.
        let second = TransactionVerification.verified(TransactionSnapshot(transactionID: 43, productID: ids.coinsSmall))
        XCTAssertEqual(PurchaseProcessor.process(second, catalog: catalog, progress: &progress).grant, .coinsGranted(500))
        XCTAssertEqual(progress.coins, 1_000)
    }

    func testUnverifiedTransactionGrantsNothingAndIsNotFinished() {
        var progress = PlayerProgress()
        for productID in catalog.allIDs {
            let result = PurchaseProcessor.process(
                .unverified(TransactionSnapshot(transactionID: 7, productID: productID)), catalog: catalog, progress: &progress)
            XCTAssertEqual(result.grant, .rejectedUnverified)
            XCTAssertFalse(result.shouldFinishTransaction)
        }
        XCTAssertEqual(progress, PlayerProgress())
    }

    func testVerifiedNonConsumablesGrantEntitlements() {
        var progress = PlayerProgress()
        let result = PurchaseProcessor.process(
            .verified(TransactionSnapshot(transactionID: 1, productID: ids.removeForcedAds)), catalog: catalog, progress: &progress)
        XCTAssertEqual(result.grant, .entitlementGranted(productID: ids.removeForcedAds))
        XCTAssertTrue(PurchaseProcessor.hasRemoveForcedAds(progress, catalog: catalog))

        _ = PurchaseProcessor.process(
            .verified(TransactionSnapshot(transactionID: 2, productID: ids.themeNebula)), catalog: catalog, progress: &progress)
        XCTAssertEqual(progress.purchasedProductIDs, [ids.removeForcedAds, ids.themeNebula])
        XCTAssertEqual(progress.coins, 0)
    }

    func testRevokedNonConsumableRemovesEntitlement() {
        var progress = PlayerProgress()
        progress.purchasedProductIDs = [ids.removeForcedAds]
        let result = PurchaseProcessor.process(
            .verified(TransactionSnapshot(transactionID: 9, productID: ids.removeForcedAds, isRevoked: true)),
            catalog: catalog, progress: &progress)
        XCTAssertEqual(result.grant, .entitlementRevoked(productID: ids.removeForcedAds))
        XCTAssertFalse(PurchaseProcessor.hasRemoveForcedAds(progress, catalog: catalog))
    }

    func testRevokedConsumableNeverGrants() {
        var progress = PlayerProgress()
        let result = PurchaseProcessor.process(
            .verified(TransactionSnapshot(transactionID: 5, productID: ids.coinsLarge, isRevoked: true)),
            catalog: catalog, progress: &progress)
        XCTAssertEqual(result.grant, .revokedConsumableIgnored)
        XCTAssertEqual(progress.coins, 0)
    }

    func testUnknownProductIsFinishedWithoutGrant() {
        var progress = PlayerProgress()
        let result = PurchaseProcessor.process(
            .verified(TransactionSnapshot(transactionID: 3, productID: "com.other.thing")), catalog: catalog, progress: &progress)
        XCTAssertEqual(result.grant, .unknownProduct)
        XCTAssertTrue(result.shouldFinishTransaction)
        XCTAssertEqual(progress, PlayerProgress())
    }

    func testRestoreRebuildsNonConsumablesOnlyFromVerifiedEntitlements() {
        var progress = PlayerProgress()
        progress.coins = 250
        progress.purchasedProductIDs = [ids.themeSunrise] // stale cache: refunded since
        let current: [TransactionVerification] = [
            .verified(TransactionSnapshot(transactionID: 10, productID: ids.removeForcedAds)),
            .verified(TransactionSnapshot(transactionID: 11, productID: ids.themeNebula)),
            .unverified(TransactionSnapshot(transactionID: 12, productID: ids.themeSunrise)),
            .verified(TransactionSnapshot(transactionID: 13, productID: ids.coinsSmall)), // consumables are not restorable
        ]
        PurchaseProcessor.reconcileEntitlements(current, catalog: catalog, progress: &progress)
        XCTAssertEqual(progress.purchasedProductIDs, [ids.removeForcedAds, ids.themeNebula])
        XCTAssertEqual(progress.coins, 250, "Restore must never touch coin balances")
    }

    func testProductKindsAreClassifiedCorrectly() {
        XCTAssertEqual(catalog.products.filter(\.kind.isConsumable).map(\.id).sorted(), [ids.coinsLarge, ids.coinsSmall].sorted())
        XCTAssertEqual(catalog.allIDs.count, Set(catalog.allIDs).count)
    }
}
