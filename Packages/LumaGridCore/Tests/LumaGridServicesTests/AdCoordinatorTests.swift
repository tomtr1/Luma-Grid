import Foundation
import XCTest
@testable import LumaGridServices

// MARK: - Test doubles (development/test only; never used by the app)

@MainActor
final class MockInterstitial: InterstitialAdProviding {
    var isReady = true
    var loadCount = 0
    var presentCount = 0
    var loadSucceeds = true

    func load() async {
        loadCount += 1
        isReady = loadSucceeds
    }

    func present() async -> Bool {
        guard isReady else { return false }
        presentCount += 1
        isReady = false
        return true
    }
}

@MainActor
final class MockRewarded: RewardedAdProviding {
    enum Behaviour { case earn(times: Int), closeEarly, failToPresent }
    var isReady = true
    var behaviour: Behaviour = .earn(times: 1)
    var presentCount = 0
    var loadSucceeds = true

    func load() async { isReady = loadSucceeds }

    func present(onEarnedReward: @escaping @MainActor () -> Void) async -> Bool {
        guard isReady else { return false }
        presentCount += 1
        isReady = false
        switch behaviour {
        case let .earn(times):
            for _ in 0..<times { onEarnedReward() }
            return true
        case .closeEarly:
            return true
        case .failToPresent:
            return false
        }
    }
}

@MainActor
final class AdHarness {
    var pacing = AdPacingState()
    var coins = 0
    var consent = true
    var removeAds = false
    var now = Date(timeIntervalSince1970: 1_000_000)
    let interstitial = MockInterstitial()
    let rewarded = MockRewarded()
    lazy var coordinator = AdCoordinator(
        policy: .standard,
        rewardedCoins: 50,
        interstitial: interstitial,
        rewarded: rewarded,
        environment: .init(
            canRequestAds: { [weak self] in self?.consent ?? false },
            hasRemoveForcedAds: { [weak self] in self?.removeAds ?? false },
            pacing: { [weak self] in self?.pacing ?? AdPacingState() },
            updatePacing: { [weak self] in self?.pacing = $0 },
            grantCoins: { [weak self] in self?.coins += $0 },
            now: { [weak self] in self?.now ?? Date() }
        )
    )

    /// Simulates finishing a round and leaving the results screen.
    func finishGame(minutesLater: Double = 4) async -> Bool {
        now = now.addingTimeInterval(minutesLater * 60)
        coordinator.recordCompletedGame()
        interstitial.isReady = true
        return await coordinator.showInterstitialIfDue()
    }
}

@MainActor
final class AdCoordinatorTests: XCTestCase {
    // MARK: Interstitial cadence

    func testNoInterstitialDuringFirstTwoGamesThenEveryThirdGame() async {
        let harness = AdHarness()
        var shown: [Bool] = []
        for _ in 1...9 { shown.append(await harness.finishGame()) }
        XCTAssertEqual(shown, [false, false, true, false, false, true, false, false, true])
        XCTAssertEqual(harness.interstitial.presentCount, 3)
    }

    func testMinimumTimeBetweenInterstitials() async {
        let harness = AdHarness()
        _ = await harness.finishGame()
        _ = await harness.finishGame()
        let value1 = await harness.finishGame()
        XCTAssertTrue(value1)
        // Three quick games (30 s apart) satisfy the game count but not the 180 s gap.
        _ = await harness.finishGame(minutesLater: 0.5)
        _ = await harness.finishGame(minutesLater: 0.5)
        let value2 = await harness.finishGame(minutesLater: 0.5)
        XCTAssertFalse(value2)
        // Once enough time passes, the next game may show one.
        let value3 = await harness.finishGame(minutesLater: 3)
        XCTAssertTrue(value3)
    }

    func testRollingHourCap() {
        var pacing = AdPacingState()
        let policy = InterstitialPolicy(graceGames: 0, minimumGamesBetween: 1, minimumSecondsBetween: 0, maximumPerRollingHour: 3)
        let start = Date(timeIntervalSince1970: 0)
        for minute in [0.0, 10, 20] {
            pacing.recordCompletedGame()
            XCTAssertTrue(pacing.isInterstitialEligible(at: start.addingTimeInterval(minute * 60), policy: policy))
            pacing.recordInterstitialShown(at: start.addingTimeInterval(minute * 60))
        }
        pacing.recordCompletedGame()
        XCTAssertFalse(pacing.isInterstitialEligible(at: start.addingTimeInterval(30 * 60), policy: policy))
        XCTAssertTrue(pacing.isInterstitialEligible(at: start.addingTimeInterval(61 * 60), policy: policy))
    }

    func testClockMovedBackwardsDoesNotAllowAnInterstitial() {
        var pacing = AdPacingState()
        let policy = InterstitialPolicy.standard
        for _ in 0..<3 { pacing.recordCompletedGame() }
        pacing.recordInterstitialShown(at: Date(timeIntervalSince1970: 10_000))
        for _ in 0..<3 { pacing.recordCompletedGame() }
        XCTAssertFalse(pacing.isInterstitialEligible(at: Date(timeIntervalSince1970: 5_000), policy: policy))
    }

    func testPacingSurvivesPersistence() throws {
        var pacing = AdPacingState()
        pacing.recordCompletedGame()
        pacing.recordInterstitialShown(at: Date(timeIntervalSince1970: 500))
        let data = try JSONEncoder().encode(pacing)
        XCTAssertEqual(try JSONDecoder().decode(AdPacingState.self, from: data), pacing)
    }

    func testRemoveForcedAdsSuppressesInterstitials() async {
        let harness = AdHarness()
        harness.removeAds = true
        for _ in 1...9 {
            let shown = await harness.finishGame()
            XCTAssertFalse(shown)
        }
        XCTAssertEqual(harness.interstitial.presentCount, 0)
        // Rewarded ads stay available because the player chooses them.
        XCTAssertTrue(harness.coordinator.isRewardedAvailable)
    }

    func testNoAdsWithoutConsentPermission() async {
        let harness = AdHarness()
        harness.consent = false
        for _ in 1...6 {
            let shown = await harness.finishGame()
            XCTAssertFalse(shown)
        }
        let value4 = await harness.coordinator.showRewarded()
        XCTAssertEqual(value4, .unavailable)
        XCTAssertEqual(harness.interstitial.presentCount + harness.rewarded.presentCount, 0)
    }

    func testInterstitialNotLoadedDoesNotBlockOrRetryShow() async {
        let harness = AdHarness()
        for _ in 1...2 { _ = await harness.finishGame() }
        harness.now = harness.now.addingTimeInterval(600)
        harness.coordinator.recordCompletedGame()
        harness.interstitial.isReady = false
        harness.interstitial.loadSucceeds = false
        let shown = await harness.coordinator.showInterstitialIfDue()
        XCTAssertFalse(shown)
        XCTAssertEqual(harness.interstitial.presentCount, 0)
        XCTAssertEqual(harness.pacing.gamesSinceLastInterstitial, 3, "A missed opportunity is not counted as shown")
    }

    // MARK: Rewarded

    func testRewardGrantedOnlyFromEarnedCallback() async {
        let harness = AdHarness()
        let value5 = await harness.coordinator.showRewarded()
        XCTAssertEqual(value5, .granted(coins: 50))
        XCTAssertEqual(harness.coins, 50)
    }

    func testDuplicateRewardCallbacksGrantOnce() async {
        let harness = AdHarness()
        harness.rewarded.behaviour = .earn(times: 3)
        let value6 = await harness.coordinator.showRewarded()
        XCTAssertEqual(value6, .granted(coins: 50))
        XCTAssertEqual(harness.coins, 50)
    }

    func testUserClosingRewardedEarlyGetsNothing() async {
        let harness = AdHarness()
        harness.rewarded.behaviour = .closeEarly
        let value7 = await harness.coordinator.showRewarded()
        XCTAssertEqual(value7, .notEarned)
        XCTAssertEqual(harness.coins, 0)
    }

    func testRewardedUnavailableOrLoadFailureLeavesBalanceUnchanged() async {
        let harness = AdHarness()
        harness.rewarded.isReady = false
        harness.rewarded.loadSucceeds = false
        await harness.coordinator.preload()
        XCTAssertFalse(harness.coordinator.isRewardedAvailable)
        let value8 = await harness.coordinator.showRewarded()
        XCTAssertEqual(value8, .unavailable)

        harness.rewarded.isReady = true
        harness.rewarded.behaviour = .failToPresent
        let value9 = await harness.coordinator.showRewarded()
        XCTAssertEqual(value9, .unavailable)
        XCTAssertEqual(harness.coins, 0)
    }

    func testRepeatedTapsWhilePresentingAreIgnored() async {
        let harness = AdHarness()
        async let first = harness.coordinator.showRewarded()
        async let second = harness.coordinator.showRewarded()
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 == .granted(coins: 50) }.count, 1)
        XCTAssertEqual(harness.coins, 50)
    }

    func testLateCallbackFromAnOldPresentationIsIgnored() {
        let guardian = RewardGrantGuard()
        let old = guardian.begin()
        guardian.end(old)
        XCTAssertFalse(guardian.claim(old))
        let current = guardian.begin()
        XCTAssertTrue(guardian.claim(current))
        XCTAssertFalse(guardian.claim(current))
    }

    // MARK: Configuration

    func testAdConfigurationValidation() {
        let testApp = "ca-app-pub-3940256099942544~1458002511"
        let testInterstitial = "ca-app-pub-3940256099942544/4411468910"
        let testRewarded = "ca-app-pub-3940256099942544/1712485313"
        let realApp = "ca-app-pub-1111111111111111~2222222222"
        let realUnit = "ca-app-pub-1111111111111111/3333333333"

        XCTAssertEqual(AdsConfiguration(applicationID: testApp, interstitialUnitID: testInterstitial, rewardedUnitID: testRewarded,
                                        isDebugBuild: true, isEnabledInBuild: true).status, .enabled(usingTestAds: true))
        // Test IDs must never ship in Release.
        guard case .disabled = AdsConfiguration(applicationID: testApp, interstitialUnitID: testInterstitial, rewardedUnitID: testRewarded,
                                                isDebugBuild: false, isEnabledInBuild: true).status else { return XCTFail() }
        // Production IDs must not be used for development traffic.
        guard case .disabled = AdsConfiguration(applicationID: realApp, interstitialUnitID: realUnit, rewardedUnitID: realUnit,
                                                isDebugBuild: true, isEnabledInBuild: true).status else { return XCTFail() }
        XCTAssertEqual(AdsConfiguration(applicationID: realApp, interstitialUnitID: realUnit, rewardedUnitID: realUnit,
                                        isDebugBuild: false, isEnabledInBuild: true).status, .enabled(usingTestAds: false))
        // Missing values or unexpanded build settings disable ads safely.
        guard case .disabled = AdsConfiguration(applicationID: "", interstitialUnitID: realUnit, rewardedUnitID: realUnit,
                                                isDebugBuild: false, isEnabledInBuild: true).status else { return XCTFail() }
        guard case .disabled = AdsConfiguration(applicationID: "$(LUMA_GAD_APP_ID)", interstitialUnitID: realUnit, rewardedUnitID: realUnit,
                                                isDebugBuild: false, isEnabledInBuild: true).status else { return XCTFail() }
        guard case .disabled = AdsConfiguration(applicationID: realApp, interstitialUnitID: realUnit, rewardedUnitID: realUnit,
                                                isDebugBuild: false, isEnabledInBuild: false).status else { return XCTFail() }
    }
}
