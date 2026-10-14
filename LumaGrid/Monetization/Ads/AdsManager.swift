import Foundation
import Observation
import LumaGridServices

/// App-facing ads facade. Owns consent, SDK start-up, and the `AdCoordinator` that enforces
/// every placement rule. Views only call `showInterstitialIfDue()` at natural breaks and
/// `showRewarded()` after the player explicitly asks. If ads are disabled, unconfigured, not
/// consented, or fail to load, every call returns immediately and the game carries on.
@MainActor
@Observable
final class AdsManager {
    private(set) var status: AdsConfiguration.Status
    private(set) var canRequestAds = false
    private(set) var isPrivacyOptionsRequired = false
    private(set) var isRewardedReady = false

    @ObservationIgnored private let configuration: AdsConfiguration
    @ObservationIgnored private let progress: ProgressStore
    @ObservationIgnored private var coordinator: AdCoordinator?
    @ObservationIgnored private var hasStarted = false

    init(configuration: AdsConfiguration, progress: ProgressStore, forceDisabled: Bool = false) {
        self.configuration = configuration
        self.progress = progress
        self.status = forceDisabled ? .disabled(reason: "Disabled for previews/tests.") : configuration.status
    }

    var isEnabled: Bool {
        if case .enabled = status { return true }
        return false
    }

    var rewardedCoins: Int { AppConfiguration.economy.rewardedAdCoins }

    /// Gathers consent (UMP) and starts the Google Mobile Ads SDK only once ads may be requested.
    func start() async {
        guard isEnabled, !hasStarted else { return }
        hasStarted = true
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        // Consent obtained in a previous session allows starting immediately.
        refreshConsentState()
        if canRequestAds { startSDKIfNeeded() }

        // Per Google's guidance, update consent information on every launch.
        _ = await ConsentCoordinator.gatherConsent()
        refreshConsentState()
        if canRequestAds { startSDKIfNeeded() }
        #else
        status = .disabled(reason: "Google Mobile Ads SDK is not linked in this build.")
        #endif
    }

    /// Call once per finished round, before the results screen appears.
    func recordCompletedGame() {
        if let coordinator {
            coordinator.recordCompletedGame()
        } else {
            // Keep pacing counts accurate even before the SDK starts (e.g. consent pending).
            progress.update { $0.adPacing.recordCompletedGame() }
        }
    }

    /// Natural break only (leaving a finished round). Returns after the ad closes, or at once.
    func showInterstitialIfDue() async {
        guard let coordinator else { return }
        await coordinator.showInterstitialIfDue()
        refreshRewardedReady()
    }

    func showRewarded() async -> RewardedOfferResult {
        guard let coordinator else { return .unavailable }
        let result = await coordinator.showRewarded()
        refreshRewardedReady()
        return result
    }

    func preload() async {
        guard let coordinator else { return }
        await coordinator.preload()
        refreshRewardedReady()
    }

    /// Lets players revisit their consent choice (required when UMP says privacy options apply).
    func presentPrivacyOptions() async {
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        await ConsentCoordinator.presentPrivacyOptions()
        refreshConsentState()
        #endif
    }

    // MARK: Private

    private func refreshConsentState() {
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        canRequestAds = ConsentCoordinator.canRequestAds
        isPrivacyOptionsRequired = ConsentCoordinator.isPrivacyOptionsRequired
        #endif
    }

    private func refreshRewardedReady() {
        isRewardedReady = coordinator?.isRewardedAvailable ?? false
    }

    private func startSDKIfNeeded() {
        #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
        guard coordinator == nil else { return }
        GoogleMobileAdsBridge.startSDK()
        let interstitial = GoogleInterstitialProvider(adUnitID: configuration.interstitialUnitID)
        let rewarded = GoogleRewardedProvider(adUnitID: configuration.rewardedUnitID)
        rewarded.onAvailabilityChange = { [weak self] in self?.refreshRewardedReady() }
        let progress = self.progress
        coordinator = AdCoordinator(
            policy: AppConfiguration.interstitialPolicy,
            rewardedCoins: AppConfiguration.economy.rewardedAdCoins,
            interstitial: interstitial,
            rewarded: rewarded,
            environment: .init(
                canRequestAds: { ConsentCoordinator.canRequestAds },
                hasRemoveForcedAds: { progress.hasRemoveForcedAds },
                pacing: { progress.progress.adPacing },
                updatePacing: { pacing in progress.update { $0.adPacing = pacing } },
                grantCoins: { coins in progress.update { $0.addCoins(coins) } }
            )
        )
        Task { await preload() }
        #endif
    }
}
