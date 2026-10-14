/// Points awarded for a single placement, itemized so the UI can show where they came from.
public struct ScoreBreakdown: Hashable, Codable, Sendable {
    public var placementPoints: Int
    public var linePoints: Int
    public var comboBonus: Int

    public init(placementPoints: Int = 0, linePoints: Int = 0, comboBonus: Int = 0) {
        self.placementPoints = placementPoints
        self.linePoints = linePoints
        self.comboBonus = comboBonus
    }

    public var total: Int { placementPoints + linePoints + comboBonus }
}

public enum ScoreCalculator {
    /// - Parameters:
    ///   - cellsPlaced: Cells in the placed piece.
    ///   - linesCleared: Rows plus columns completed by this placement.
    ///   - comboStreak: Consecutive line-clearing placements including this one (0 if none cleared).
    public static func score(cellsPlaced: Int, linesCleared: Int, comboStreak: Int, rules: ScoringRules) -> ScoreBreakdown {
        let placement = cellsPlaced * rules.pointsPerCell
        let lines = rules.pointsPerLine * linesCleared * linesCleared
        let combo = linesCleared > 0 ? rules.comboBonusPerStep * max(0, comboStreak - 1) : 0
        return ScoreBreakdown(placementPoints: placement, linePoints: lines, comboBonus: combo)
    }
}
