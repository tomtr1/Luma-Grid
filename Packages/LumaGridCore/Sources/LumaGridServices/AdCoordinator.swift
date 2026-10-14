import Foundation

/// A loaded-or-not interstitial source (Google Mobile Ads in the app, a mock in tests).
@MainActor
public protocol InterstitialAdProviding: AnyObject {
    var isReady: Bool { get }
    func load() async
    /// Presents the ad if one is loaded and returns once it is dismissed.
    /// Returns false if nothing could be shown.
    func present() async -> Bool
}

/// A rewarded ad source. `onEarnedReward` must be wired to the SDK's earned-reward callback only.
@MainActor
public protocol RewardedAdProviding: AnyObject {
    var isReady: Bool { get }
    func load() async
    /// Presents the ad and returns once it is dismissed (or failed to present).
    /// Returns false if nothing could be shown. `onEarnedReward` may be called zero or more times.
    func present(onEarnedReward: @escaping @MainActor () -> Void) async -> Bool
}

public enum RewardedOfferResult: Equatable, Sendable {
    case granted(coins: Int)
    /// The ad was shown but closed before the reward was earned.
    case notEarned
    /// No ad is loaded, consent does not permit ads, or ads are disabled.
    case unavailable
    /// A rewarded ad is already on screen; repeated taps are ignored.
    case alreadyInProgress
}

/// Grants a reward at most once per presentation, however many times the SDK calls back.
@MainActor
public final class RewardGrantGuard {
    private var activeToken: UUID?
    private var grantedTokens: Set<UUID> = []

    public init() {}

    public func begin() -> UUID {
        let token = UUID()
        activeToken = token
        return token
    }

    /// Returns true exactly once for a token that is still active.
    public func claim(_ token: UUID) -> Bool {
        guard token == activeToken, !grantedTokens.contains(token) else { return false }
        grantedTokens.insert(token)
        return true
    }

    public func end(_ token: UUID) {
        if activeToken == token { activeToken = nil }
    }
}

/// Orchestrates when ads may appear. Contains every rule (consent, frequency caps,
/// Remove Forced Ads entitlement, single reward grant), so SwiftUI views just ask it.
@MainActor
public final class AdCoordinator {
    public struct Environment {
        public var canRequestAds: @MainActor () -> Bool
        public var hasRemoveForcedAds: @MainActor () -> Bool
        public var pacing: @MainActor () -> AdPacingState
        public var updatePacing: @MainActor (AdPacingState) -> Void
        public var grantCoins: @MainActor (Int) -> Void
        public var now: @MainActor () -> Date

        public init(
            canRequestAds: @escaping @MainActor () -> Bool,
            hasRemoveForcedAds: @escaping @MainActor () -> Bool,
            pacing: @escaping @MainActor () -> AdPacingState,
            updatePacing: @escaping @MainActor (AdPacingState) -> Void,
            grantCoins: @escaping @MainActor (Int) -> Void,
            now: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.canRequestAds = canRequestAds
            self.hasRemoveForcedAds = hasRemoveForcedAds
            self.pacing = pacing
            self.updatePacing = updatePacing
            self.grantCoins = grantCoins
            self.now = now
        }
    }

    public let policy: InterstitialPolicy
    public let rewardedCoins: Int
    private let interstitial: InterstitialAdProviding?
    private let rewarded: RewardedAdProviding?
    private let environment: Environment
    private let rewardGuard = RewardGrantGuard()
    private var isPresenting = false

    public init(policy: InterstitialPolicy, rewardedCoins: Int, interstitial: InterstitialAdProviding?,
                rewarded: RewardedAdProviding?, environment: Environment) {
        self.policy = policy
        self.rewardedCoins = rewardedCoins
        self.interstitial = interstitial
        self.rewarded = rewarded
        self.environment = environment
    }

    public var isRewardedAvailable: Bool {
        environment.canRequestAds() && (rewarded?.isReady ?? false) && !isPresenting
    }

    /// Loads whatever is needed and allowed. Safe to call repeatedly; never blocks gameplay.
    public func preload() async {
        guard environment.canRequestAds() else { return }
        if let interstitial, !environment.hasRemoveForcedAds(), !interstitial.isReady {
            await interstitial.load()
        }
        if let rewarded, !rewarded.isReady {
            await rewarded.load()
        }
    }

    /// Call once per finished round.
    public func recordCompletedGame() {
        var pacing = environment.pacing()
        pacing.recordCompletedGame()
        environment.updatePacing(pacing)
    }

    public func isInterstitialDue() -> Bool {
        guard !environment.hasRemoveForcedAds(), environment.canRequestAds() else { return false }
        return environment.pacing().isInterstitialEligible(at: environment.now(), policy: policy)
    }

    /// Shows an interstitial only at a natural break, only when caps allow and one is already
    /// loaded. Returns immediately (false) otherwise; the caller then continues normally.
    @discardableResult
    public func showInterstitialIfDue() async -> Bool {
        guard !isPresenting, isInterstitialDue(), let interstitial, interstitial.isReady else { return false }
        isPresenting = true
        defer { isPresenting = false }
        let shown = await interstitial.present()
        if shown {
            var pacing = environment.pacing()
            pacing.recordInterstitialShown(at: environment.now())
            environment.updatePacing(pacing)
        }
        Task { await self.preload() }
        return shown
    }

    /// Shows a rewarded ad the player explicitly asked for. Coins are granted only from the
    /// earned-reward callback, at most once.
    public func showRewarded() async -> RewardedOfferResult {
        guard !isPresenting else { return .alreadyInProgress }
        guard environment.canRequestAds(), let rewarded, rewarded.isReady else { return .unavailable }
        isPresenting = true
        defer { isPresenting = false }

        let token = rewardGuard.begin()
        var granted = false
        let amount = rewardedCoins
        let shown = await rewarded.present { [weak self] in
            guard let self, self.rewardGuard.claim(token) else { return }
            granted = true
            self.environment.grantCoins(amount)
        }
        rewardGuard.end(token)
        Task { await self.preload() }

        if granted { return .granted(coins: amount) }
        return shown ? .notEarned : .unavailable
    }
}
