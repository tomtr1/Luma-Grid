/// Every tunable rule lives here so balance changes never require hunting for magic numbers.
public struct GameConfiguration: Hashable, Codable, Sendable {
    public var boardSize: Int
    public var traySize: Int
    /// Number of distinct tile colors the generator chooses from (the theme supplies the colors).
    public var paletteSize: Int
    public var catalog: [PieceDefinition]
    public var scoring: ScoringRules
    public var lumen: LumenRules
    public var generation: GenerationRules

    public init(
        boardSize: Int = 9,
        traySize: Int = 3,
        paletteSize: Int = 5,
        catalog: [PieceDefinition] = PieceCatalog.standard,
        scoring: ScoringRules = .standard,
        lumen: LumenRules = .standard,
        generation: GenerationRules = .standard
    ) {
        self.boardSize = boardSize
        self.traySize = traySize
        self.paletteSize = paletteSize
        self.catalog = catalog
        self.scoring = scoring
        self.lumen = lumen
        self.generation = generation
    }

    public static let standard = GameConfiguration()
}

/// Scoring formula (see `ScoreCalculator`):
///
///     placement = cellsPlaced × pointsPerCell
///     lines     = pointsPerLine × linesCleared²        (rewards multi-line clears)
///     combo     = comboBonusPerStep × (comboStreak − 1) when the move clears ≥ 1 line
///     total     = placement + lines + combo
public struct ScoringRules: Hashable, Codable, Sendable {
    public var pointsPerCell: Int
    public var pointsPerLine: Int
    public var comboBonusPerStep: Int

    public init(pointsPerCell: Int, pointsPerLine: Int, comboBonusPerStep: Int) {
        self.pointsPerCell = pointsPerCell
        self.pointsPerLine = pointsPerLine
        self.comboBonusPerStep = comboBonusPerStep
    }

    public static let standard = ScoringRules(pointsPerCell: 1, pointsPerLine: 10, comboBonusPerStep: 15)
}

public struct LumenRules: Hashable, Codable, Sendable {
    /// Charges needed before Pulse is ready.
    public var chargesForPulse: Int
    /// Side length of the square Pulse clears (3 → a 3×3 area).
    public var pulseAreaSide: Int

    public init(chargesForPulse: Int, pulseAreaSide: Int) {
        self.chargesForPulse = chargesForPulse
        self.pulseAreaSide = pulseAreaSide
    }

    public static let standard = LumenRules(chargesForPulse: 3, pulseAreaSide: 3)
}

public struct GenerationRules: Hashable, Codable, Sendable {
    /// Probability that a generated piece carries one Prism Cell.
    public var prismChance: Double
    /// Upper bound on Prism pieces in a single tray, so they stay special.
    public var maxPrismPiecesPerTray: Int
    /// When > 0, the generator redraws a fresh tray (up to this many times) until at least one
    /// piece fits the current board. This never alters the board and is identical for every
    /// player regardless of purchases; it only avoids dealing an instantly dead tray.
    public var playableTrayAttempts: Int

    public init(prismChance: Double, maxPrismPiecesPerTray: Int, playableTrayAttempts: Int) {
        self.prismChance = prismChance
        self.maxPrismPiecesPerTray = maxPrismPiecesPerTray
        self.playableTrayAttempts = playableTrayAttempts
    }

    public static let standard = GenerationRules(prismChance: 0.14, maxPrismPiecesPerTray: 1, playableTrayAttempts: 10)
}
