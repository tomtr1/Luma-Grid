#if canImport(GoogleMobileAds)
@preconcurrency import GoogleMobileAds
import UIKit
import LumaGridServices

/// Thin wrappers that adapt the Google Mobile Ads SDK (v12+ Swift API names) to the
/// `InterstitialAdProviding` / `RewardedAdProviding` protocols. All placement rules live in
/// `AdCoordinator`; these classes only load and present.
enum GoogleMobileAdsBridge {
    @MainActor
    static func startSDK() {
        MobileAds.shared.start()
    }
}

@MainActor
final class GoogleInterstitialProvider: NSObject, InterstitialAdProviding, FullScreenContentDelegate {
    private let adUnitID: String
    private var ad: InterstitialAd?
    private var isLoading = false
    private var dismissal: CheckedContinuation<Bool, Never>?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    var isReady: Bool { ad != nil }

    func load() async {
        guard !isLoading, ad == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await InterstitialAd.load(with: adUnitID, request: Request())
            loaded.fullScreenContentDelegate = self
            ad = loaded
        } catch {
            ad = nil // Load failures are expected (no fill, offline); the game simply continues.
        }
    }

    func present() async -> Bool {
        guard let ad, dismissal == nil, let presenter = UIApplication.shared.lumaTopViewController else { return false }
        return await withCheckedContinuation { continuation in
            dismissal = continuation
            ad.present(from: presenter)
        }
    }

    private func finish(shown: Bool) {
        ad = nil
        dismissal?.resume(returning: shown)
        dismissal = nil
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish(shown: true) }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish(shown: false) }
    }
}

@MainActor
final class GoogleRewardedProvider: NSObject, RewardedAdProviding, FullScreenContentDelegate {
    private let adUnitID: String
    private var ad: RewardedAd?
    private var isLoading = false
    private var dismissal: CheckedContinuation<Bool, Never>?
    var onAvailabilityChange: (() -> Void)?

    init(adUnitID: String) {
        self.adUnitID = adUnitID
    }

    var isReady: Bool { ad != nil }

    func load() async {
        guard !isLoading, ad == nil else { return }
        isLoading = true
        defer {
            isLoading = false
            onAvailabilityChange?()
        }
        do {
            let loaded = try await RewardedAd.load(with: adUnitID, request: Request())
            loaded.fullScreenContentDelegate = self
            ad = loaded
        } catch {
            ad = nil
        }
    }

    func present(onEarnedReward: @escaping @MainActor () -> Void) async -> Bool {
        guard let ad, dismissal == nil, let presenter = UIApplication.shared.lumaTopViewController else { return false }
        return await withCheckedContinuation { continuation in
            dismissal = continuation
            // The SDK calls this handler only when the user has earned the reward.
            // The coin amount is LumaGrid's fixed, pre-announced amount, not the ad network's.
            ad.present(from: presenter) {
                onEarnedReward()
            }
        }
    }

    private func finish(shown: Bool) {
        ad = nil
        dismissal?.resume(returning: shown)
        dismissal = nil
        onAvailabilityChange?()
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish(shown: true) }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish(shown: false) }
    }
}
#endif
