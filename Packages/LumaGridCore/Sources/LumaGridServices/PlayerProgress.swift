import Foundation
import LumaGridEngine

/// Everything LumaGrid stores on the device. Versioned and tolerant: every field decodes with a
/// default, so missing keys (older saves) or extra keys (newer saves) never crash the app.
public struct PlayerProgress: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = PlayerProgress.currentSchemaVersion
    public var bestScore: Int = 0
    public var coins: Int = 0
    /// Themes unlocked with coins. Purchased themes come from `purchasedProductIDs`.
    public var unlockedThemeIDs: Set<String> = []
    /// Cache of verified, non-revoked non-consumable StoreKit entitlements. Rebuilt from
    /// `Transaction.currentEntitlements` on launch and on Restore Purchases.
    public var purchasedProductIDs: Set<String> = []
    public var selectedThemeID: String = ThemeCatalog.defaultThemeID
    public var settings = GameSettings()
    public var tutorialCompleted = false
    public var stats = LifetimeStats()
    public var adPacing = AdPacingState()
    /// Consumable transactions already credited. Prevents double grants if StoreKit re-delivers
    /// a transaction (for example after a crash before `finish()`).
    public var processedTransactionIDs: Set<String> = []
    public var daily = DailyRecord()
    /// An unfinished round, saved after every move so it survives termination.
    public var savedGame: GameSession?

    public init() {}
}

public struct GameSettings: Equatable, Codable, Sendable {
    public var soundEnabled = true
    public var hapticsEnabled = true
    /// In-game preference that adds to (never overrides) the system Reduce Motion setting.
    public var reduceMotion = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
    }
}

public struct LifetimeStats: Equatable, Codable, Sendable {
    public var gamesPlayed = 0
    public var linesCleared = 0
    public var totalScore = 0
    public var pulsesUsed = 0
    public var bestComboStreak = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gamesPlayed = try container.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        linesCleared = try container.decodeIfPresent(Int.self, forKey: .linesCleared) ?? 0
        totalScore = try container.decodeIfPresent(Int.self, forKey: .totalScore) ?? 0
        pulsesUsed = try container.decodeIfPresent(Int.self, forKey: .pulsesUsed) ?? 0
        bestComboStreak = try container.decodeIfPresent(Int.self, forKey: .bestComboStreak) ?? 0
    }
}

public struct DailyRecord: Equatable, Codable, Sendable {
    /// Best score per daily date key ("YYYY-MM-DD"). Trimmed to the most recent entries.
    public var bestScores: [String: Int] = [:]
    /// Date keys whose completion bonus has already been paid.
    public var bonusPaidDateKeys: Set<String> = []

    public static let retainedDays = 30

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bestScores = try container.decodeIfPresent([String: Int].self, forKey: .bestScores) ?? [:]
        bonusPaidDateKeys = try container.decodeIfPresent(Set<String>.self, forKey: .bonusPaidDateKeys) ?? []
    }

    mutating func trim() {
        // Date keys sort lexicographically in chronological order.
        let allKeys = Set(bestScores.keys).union(bonusPaidDateKeys)
        let keep = Set(allKeys.sorted().suffix(Self.retainedDays))
        bestScores = bestScores.filter { keep.contains($0.key) }
        bonusPaidDateKeys = bonusPaidDateKeys.intersection(keep)
    }
}

extension PlayerProgress: Codable {
    enum CodingKeys: String, CodingKey {
        case schemaVersion, bestScore, coins, unlockedThemeIDs, purchasedProductIDs, selectedThemeID
        case settings, tutorialCompleted, stats, adPacing, processedTransactionIDs, daily, savedGame
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        bestScore = max(0, try c.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0)
        coins = max(0, try c.decodeIfPresent(Int.self, forKey: .coins) ?? 0)
        unlockedThemeIDs = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedThemeIDs) ?? []
        purchasedProductIDs = try c.decodeIfPresent(Set<String>.self, forKey: .purchasedProductIDs) ?? []
        selectedThemeID = try c.decodeIfPresent(String.self, forKey: .selectedThemeID) ?? ThemeCatalog.defaultThemeID
        settings = (try? c.decodeIfPresent(GameSettings.self, forKey: .settings)) ?? GameSettings()
        tutorialCompleted = try c.decodeIfPresent(Bool.self, forKey: .tutorialCompleted) ?? false
        stats = (try? c.decodeIfPresent(LifetimeStats.self, forKey: .stats)) ?? LifetimeStats()
        adPacing = (try? c.decodeIfPresent(AdPacingState.self, forKey: .adPacing)) ?? AdPacingState()
        processedTransactionIDs = try c.decodeIfPresent(Set<String>.self, forKey: .processedTransactionIDs) ?? []
        daily = (try? c.decodeIfPresent(DailyRecord.self, forKey: .daily)) ?? DailyRecord()
        // A saved game from an incompatible build is dropped rather than blocking the whole save.
        savedGame = try? c.decodeIfPresent(GameSession.self, forKey: .savedGame)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(bestScore, forKey: .bestScore)
        try c.encode(coins, forKey: .coins)
        try c.encode(unlockedThemeIDs.sorted(), forKey: .unlockedThemeIDs)
        try c.encode(purchasedProductIDs.sorted(), forKey: .purchasedProductIDs)
        try c.encode(selectedThemeID, forKey: .selectedThemeID)
        try c.encode(settings, forKey: .settings)
        try c.encode(tutorialCompleted, forKey: .tutorialCompleted)
        try c.encode(stats, forKey: .stats)
        try c.encode(adPacing, forKey: .adPacing)
        try c.encode(processedTransactionIDs.sorted(), forKey: .processedTransactionIDs)
        try c.encode(daily, forKey: .daily)
        try c.encodeIfPresent(savedGame, forKey: .savedGame)
    }
}
