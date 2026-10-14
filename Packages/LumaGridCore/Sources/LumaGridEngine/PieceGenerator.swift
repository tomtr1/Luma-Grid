/// Deals trays of pieces from the catalogue using an injected, seedable random source.
/// The generator knows nothing about the player: purchases and ads cannot influence it.
public struct PieceGenerator: Hashable, Codable, Sendable {
    public private(set) var random: SplitMix64
    public private(set) var nextPieceID: Int

    public init(seed: UInt64) {
        self.random = SplitMix64(seed: seed)
        self.nextPieceID = 1
    }

    /// Generates a tray for `board`. If `generation.playableTrayAttempts > 0`, redraws until at
    /// least one piece has a legal placement (or attempts run out, in which case the last tray
    /// is used and the round may end, which is the honest outcome).
    public mutating func makeTray(for board: BoardState, configuration: GameConfiguration) -> [PieceInstance] {
        let attempts = max(1, configuration.generation.playableTrayAttempts)
        var tray: [PieceInstance] = []
        for _ in 0..<attempts {
            tray = drawTray(configuration: configuration)
            if configuration.generation.playableTrayAttempts == 0 { break }
            if tray.contains(where: board.hasLegalPlacement(for:)) { break }
        }
        return tray
    }

    private mutating func drawTray(configuration: GameConfiguration) -> [PieceInstance] {
        var prismPieces = 0
        return (0..<configuration.traySize).map { _ in
            let definition = drawDefinition(from: configuration.catalog)
            let colorIndex = random.nextInt(below: max(1, configuration.paletteSize))
            var prismIndex: Int?
            let rules = configuration.generation
            if prismPieces < rules.maxPrismPiecesPerTray, random.nextUnit() < rules.prismChance {
                prismIndex = random.nextInt(below: definition.cells.count)
                prismPieces += 1
            }
            defer { nextPieceID += 1 }
            return PieceInstance(id: nextPieceID, definition: definition, colorIndex: colorIndex, prismCellIndex: prismIndex)
        }
    }

    private mutating func drawDefinition(from catalog: [PieceDefinition]) -> PieceDefinition {
        let totalWeight = catalog.reduce(0) { $0 + $1.weight }
        precondition(totalWeight > 0, "Catalogue must contain at least one weighted piece")
        var roll = random.nextInt(below: totalWeight)
        for definition in catalog {
            if roll < definition.weight { return definition }
            roll -= definition.weight
        }
        return catalog[catalog.count - 1]
    }
}
