/// Summary of a finished round, shown on the results screen and folded into player progress.
public struct GameResult: Hashable, Codable, Sendable {
    public let mode: GameMode
    public let score: Int
    public let previousBestScore: Int
    public let linesCleared: Int
    public let bestComboStreak: Int
    public let pulsesUsed: Int
    public let placements: Int
    public let coinsEarned: Int

    public init(mode: GameMode, score: Int, previousBestScore: Int, linesCleared: Int,
                bestComboStreak: Int, pulsesUsed: Int, placements: Int, coinsEarned: Int) {
        self.mode = mode
        self.score = score
        self.previousBestScore = previousBestScore
        self.linesCleared = linesCleared
        self.bestComboStreak = bestComboStreak
        self.pulsesUsed = pulsesUsed
        self.placements = placements
        self.coinsEarned = coinsEarned
    }

    public var isNewBest: Bool { score > previousBestScore }
    public var bestScore: Int { max(score, previousBestScore) }
}

/// Coin payouts. Kept modest so purchases and cosmetics stay meaningful without making
/// free players grind; nothing here depends on whether the player has paid.
public struct EconomyConfiguration: Hashable, Codable, Sendable {
    /// Coins for finishing any round.
    public var baseRoundReward: Int
    /// One extra coin per this many points.
    public var pointsPerBonusCoin: Int
    /// Cap on the per-round reward (before the daily bonus).
    public var maxRoundReward: Int
    /// Extra coins the first time the player finishes the daily puzzle on a given day.
    public var dailyCompletionBonus: Int
    /// Fixed amount granted by an optional rewarded ad. Stated to the player before the ad.
    public var rewardedAdCoins: Int

    public init(baseRoundReward: Int, pointsPerBonusCoin: Int, maxRoundReward: Int, dailyCompletionBonus: Int, rewardedAdCoins: Int) {
        self.baseRoundReward = baseRoundReward
        self.pointsPerBonusCoin = pointsPerBonusCoin
        self.maxRoundReward = maxRoundReward
        self.dailyCompletionBonus = dailyCompletionBonus
        self.rewardedAdCoins = rewardedAdCoins
    }

    public static let standard = EconomyConfiguration(
        baseRoundReward: 5,
        pointsPerBonusCoin: 100,
        maxRoundReward: 40,
        dailyCompletionBonus: 25,
        rewardedAdCoins: 50
    )
}

public enum RoundRewardCalculator {
    /// coins = min(maxRoundReward, baseRoundReward + score / pointsPerBonusCoin)
    /// The daily-completion bonus is granted separately (once per day) by the progress layer.
    public static func coins(forScore score: Int, mode: GameMode, economy: EconomyConfiguration) -> Int {
        let bonus = economy.pointsPerBonusCoin > 0 ? max(0, score) / economy.pointsPerBonusCoin : 0
        return min(economy.maxRoundReward, economy.baseRoundReward + bonus)
    }
}

/// Deterministic daily puzzle: the same calendar date always yields the same seed and pieces.
public enum DailyChallenge {
    public static func dateKey(year: Int, month: Int, day: Int) -> String {
        let monthString = month < 10 ? "0\(month)" : "\(month)"
        let dayString = day < 10 ? "0\(day)" : "\(day)"
        return "\(year)-\(monthString)-\(dayString)"
    }

    public static func seed(forDateKey dateKey: String) -> UInt64 {
        StableHash.fnv1a("lumagrid-daily-v1-" + dateKey)
    }

    public static func makeSession(dateKey: String, configuration: GameConfiguration = .standard) -> GameSession {
        GameSession(configuration: configuration, mode: .daily(dateKey: dateKey), seed: seed(forDateKey: dateKey))
    }
}
