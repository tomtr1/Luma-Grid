import Foundation

/// Frequency caps for forced (interstitial) ads. Conservative defaults; tune only after
/// usability testing.
public struct InterstitialPolicy: Hashable, Codable, Sendable {
    /// No interstitials until the player has completed more than this many games.
    public var graceGames: Int
    /// At least this many completed games between interstitials.
    public var minimumGamesBetween: Int
    /// At least this many seconds between interstitials.
    public var minimumSecondsBetween: TimeInterval
    /// At most this many interstitials in any rolling hour.
    public var maximumPerRollingHour: Int

    public init(graceGames: Int, minimumGamesBetween: Int, minimumSecondsBetween: TimeInterval, maximumPerRollingHour: Int) {
        self.graceGames = graceGames
        self.minimumGamesBetween = minimumGamesBetween
        self.minimumSecondsBetween = minimumSecondsBetween
        self.maximumPerRollingHour = maximumPerRollingHour
    }

    public static let standard = InterstitialPolicy(graceGames: 2, minimumGamesBetween: 3, minimumSecondsBetween: 180, maximumPerRollingHour: 3)
}

/// Persisted pacing counters. Stored with player progress so restarting the app or screens
/// cannot bypass the caps.
public struct AdPacingState: Hashable, Codable, Sendable {
    public var completedGames = 0
    public var gamesSinceLastInterstitial = 0
    public var interstitialDates: [Date] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedGames = try c.decodeIfPresent(Int.self, forKey: .completedGames) ?? 0
        gamesSinceLastInterstitial = try c.decodeIfPresent(Int.self, forKey: .gamesSinceLastInterstitial) ?? 0
        interstitialDates = try c.decodeIfPresent([Date].self, forKey: .interstitialDates) ?? []
    }

    public mutating func recordCompletedGame() {
        completedGames += 1
        gamesSinceLastInterstitial += 1
    }

    public mutating func recordInterstitialShown(at date: Date) {
        gamesSinceLastInterstitial = 0
        interstitialDates.append(date)
        interstitialDates = interstitialDates.filter { date.timeIntervalSince($0) < 3_600 }
    }

    public func isInterstitialEligible(at now: Date, policy: InterstitialPolicy) -> Bool {
        guard completedGames > policy.graceGames else { return false }
        guard gamesSinceLastInterstitial >= policy.minimumGamesBetween else { return false }
        if let last = interstitialDates.max() {
            let elapsed = now.timeIntervalSince(last)
            // A clock moved backwards counts as "too recent", never as permission.
            guard elapsed >= policy.minimumSecondsBetween else { return false }
        }
        let lastHour = interstitialDates.filter { now.timeIntervalSince($0) < 3_600 && now >= $0 }
        return lastHour.count < policy.maximumPerRollingHour
    }
}

/// Validates ad unit configuration so test IDs never ship and production IDs are never used
/// for development traffic.
public struct AdsConfiguration: Hashable, Sendable {
    public static let googleTestPublisherID = "ca-app-pub-3940256099942544"

    public let applicationID: String
    public let interstitialUnitID: String
    public let rewardedUnitID: String
    public let isDebugBuild: Bool
    /// Master switch from build settings (`LUMA_ADS_ENABLED`).
    public let isEnabledInBuild: Bool

    public init(applicationID: String, interstitialUnitID: String, rewardedUnitID: String, isDebugBuild: Bool, isEnabledInBuild: Bool) {
        self.applicationID = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.interstitialUnitID = interstitialUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rewardedUnitID = rewardedUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isDebugBuild = isDebugBuild
        self.isEnabledInBuild = isEnabledInBuild
    }

    public enum Status: Equatable, Sendable {
        case enabled(usingTestAds: Bool)
        case disabled(reason: String)
    }

    public var status: Status {
        guard isEnabledInBuild else { return .disabled(reason: "Ads are switched off for this build (LUMA_ADS_ENABLED).") }
        let ids = [applicationID, interstitialUnitID, rewardedUnitID]
        guard ids.allSatisfy(Self.looksLikeAdMobID) else {
            return .disabled(reason: "AdMob app ID or ad unit IDs are missing or malformed.")
        }
        let testCount = ids.filter { $0.hasPrefix(Self.googleTestPublisherID) }.count
        if isDebugBuild {
            guard testCount == ids.count else {
                return .disabled(reason: "Debug builds must use Google's official test ad IDs.")
            }
            return .enabled(usingTestAds: true)
        } else {
            guard testCount == 0 else {
                return .disabled(reason: "Release builds must not ship Google sample/test ad IDs.")
            }
            return .enabled(usingTestAds: false)
        }
    }

    static func looksLikeAdMobID(_ id: String) -> Bool {
        id.hasPrefix("ca-app-pub-") && (id.contains("~") || id.contains("/")) && !id.contains("$(")
    }
}
