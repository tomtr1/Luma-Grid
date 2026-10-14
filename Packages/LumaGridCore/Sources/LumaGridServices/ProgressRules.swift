import LumaGridEngine

/// Coins paid out when a finished round is recorded.
public struct RoundPayout: Equatable, Sendable {
    public var roundCoins: Int
    public var dailyBonusCoins: Int
    public var total: Int { roundCoins + dailyBonusCoins }
}

public enum ThemeUnlockResult: Equatable, Sendable {
    case unlocked
    case alreadyUnlocked
    case insufficientCoins(needed: Int)
    case requiresPurchase(productID: String)
    case unknownTheme
}

extension PlayerProgress {
    /// Folds a finished round into progress: best score, stats, coins, daily record.
    /// Clears the saved game, because the round is over.
    @discardableResult
    public mutating func record(_ result: GameResult, economy: EconomyConfiguration) -> RoundPayout {
        bestScore = max(bestScore, result.score)
        stats.gamesPlayed += 1
        stats.linesCleared += result.linesCleared
        stats.totalScore += result.score
        stats.pulsesUsed += result.pulsesUsed
        stats.bestComboStreak = max(stats.bestComboStreak, result.bestComboStreak)

        var dailyBonus = 0
        if case let .daily(dateKey) = result.mode {
            daily.bestScores[dateKey] = max(daily.bestScores[dateKey] ?? 0, result.score)
            if !daily.bonusPaidDateKeys.contains(dateKey) {
                daily.bonusPaidDateKeys.insert(dateKey)
                dailyBonus = economy.dailyCompletionBonus
            }
            daily.trim()
        }

        let payout = RoundPayout(roundCoins: result.coinsEarned, dailyBonusCoins: dailyBonus)
        coins += payout.total
        savedGame = nil
        return payout
    }

    public mutating func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        coins += amount
    }

    // MARK: Themes

    public func isThemeUnlocked(_ theme: ThemeDefinition) -> Bool {
        switch theme.unlock {
        case .free: return true
        case .coins: return unlockedThemeIDs.contains(theme.id)
        case let .purchase(productID): return purchasedProductIDs.contains(productID)
        }
    }

    public mutating func unlockThemeWithCoins(_ theme: ThemeDefinition) -> ThemeUnlockResult {
        if isThemeUnlocked(theme) { return .alreadyUnlocked }
        switch theme.unlock {
        case .free:
            return .alreadyUnlocked
        case let .purchase(productID):
            return .requiresPurchase(productID: productID)
        case let .coins(price):
            guard coins >= price else { return .insufficientCoins(needed: price - coins) }
            coins -= price
            unlockedThemeIDs.insert(theme.id)
            return .unlocked
        }
    }

    /// Selects a theme if it is unlocked; otherwise leaves the selection unchanged.
    @discardableResult
    public mutating func selectTheme(_ theme: ThemeDefinition) -> Bool {
        guard isThemeUnlocked(theme) else { return false }
        selectedThemeID = theme.id
        return true
    }

    /// Falls back to the default theme if the selected one is no longer available
    /// (for example, a refunded theme pack).
    public mutating func validateSelectedTheme(in catalog: [ThemeDefinition]) {
        guard let theme = catalog.first(where: { $0.id == selectedThemeID }), isThemeUnlocked(theme) else {
            selectedThemeID = ThemeCatalog.defaultThemeID
            return
        }
    }
}
