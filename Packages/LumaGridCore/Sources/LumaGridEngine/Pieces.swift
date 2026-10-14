/// A shape from the curated catalogue. Cells are normalized so the top-left of the
/// bounding box is (0,0). Pieces do not rotate in version one; each orientation is its
/// own definition so frequencies can be tuned independently.
public struct PieceDefinition: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let cells: [GridPoint]
    /// Relative frequency within the catalogue. 0 disables the shape.
    public let weight: Int

    public init(id: String, cells: [GridPoint], weight: Int) {
        precondition(!cells.isEmpty, "A piece needs at least one cell")
        precondition(weight >= 0, "Weights cannot be negative")
        self.id = id
        self.cells = PieceDefinition.normalize(cells)
        self.weight = weight
    }

    /// Convenience initializer from an ASCII drawing, e.g. ["X.", "XX"].
    public init(id: String, weight: Int, pattern: [String]) {
        var cells: [GridPoint] = []
        for (row, line) in pattern.enumerated() {
            for (column, character) in line.enumerated() where character == "X" {
                cells.append(GridPoint(row: row, column: column))
            }
        }
        self.init(id: id, cells: cells, weight: weight)
    }

    public var width: Int { (cells.map(\.column).max() ?? 0) + 1 }
    public var height: Int { (cells.map(\.row).max() ?? 0) + 1 }

    /// True when all cells form one orthogonally connected group.
    public var isOrthogonallyConnected: Bool {
        let all = Set(cells)
        var visited: Set<GridPoint> = [cells[0]]
        var frontier = [cells[0]]
        while let current = frontier.popLast() {
            for step in [GridPoint(row: 1, column: 0), GridPoint(row: -1, column: 0),
                         GridPoint(row: 0, column: 1), GridPoint(row: 0, column: -1)] {
                let next = current + step
                if all.contains(next), visited.insert(next).inserted {
                    frontier.append(next)
                }
            }
        }
        return visited.count == all.count
    }

    static func normalize(_ cells: [GridPoint]) -> [GridPoint] {
        let minRow = cells.map(\.row).min() ?? 0
        let minColumn = cells.map(\.column).min() ?? 0
        return cells
            .map { GridPoint(row: $0.row - minRow, column: $0.column - minColumn) }
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }
}

/// A concrete piece in the tray: a definition plus color and optional Prism Cell.
public struct PieceInstance: Hashable, Codable, Sendable, Identifiable {
    /// Unique within a game session; lets the UI animate pieces stably.
    public let id: Int
    public let definitionID: String
    public let cells: [GridPoint]
    public let colorIndex: Int
    /// Index into `cells` of the Prism Cell, if this piece carries one.
    public let prismCellIndex: Int?

    public init(id: Int, definition: PieceDefinition, colorIndex: Int, prismCellIndex: Int? = nil) {
        if let prismCellIndex {
            precondition(definition.cells.indices.contains(prismCellIndex), "Prism index out of range")
        }
        self.id = id
        self.definitionID = definition.id
        self.cells = definition.cells
        self.colorIndex = colorIndex
        self.prismCellIndex = prismCellIndex
    }

    public var width: Int { (cells.map(\.column).max() ?? 0) + 1 }
    public var height: Int { (cells.map(\.row).max() ?? 0) + 1 }
    public var hasPrism: Bool { prismCellIndex != nil }

    public func tile(forCellAt index: Int) -> Tile {
        Tile(colorIndex: colorIndex, isPrism: index == prismCellIndex)
    }
}

/// The three-slot tray. A slot becomes nil once its piece is placed.
public struct PieceTrayState: Hashable, Codable, Sendable {
    public private(set) var slots: [PieceInstance?]

    public init(pieces: [PieceInstance]) {
        self.slots = pieces
    }

    public init(slots: [PieceInstance?]) {
        self.slots = slots
    }

    public var remainingPieces: [PieceInstance] { slots.compactMap { $0 } }
    public var isEmpty: Bool { remainingPieces.isEmpty }

    public func piece(inSlot slot: Int) -> PieceInstance? {
        slots.indices.contains(slot) ? slots[slot] : nil
    }

    mutating func removePiece(inSlot slot: Int) {
        slots[slot] = nil
    }
}

/// The curated set of shapes, all 1–5 cells.
public enum PieceCatalog {
    public static let standard: [PieceDefinition] = [
        // 1 cell
        PieceDefinition(id: "dot", weight: 4, pattern: ["X"]),
        // 2 cells
        PieceDefinition(id: "duo-h", weight: 6, pattern: ["XX"]),
        PieceDefinition(id: "duo-v", weight: 6, pattern: ["X", "X"]),
        // 3 cells
        PieceDefinition(id: "tri-h", weight: 6, pattern: ["XXX"]),
        PieceDefinition(id: "tri-v", weight: 6, pattern: ["X", "X", "X"]),
        PieceDefinition(id: "elbow-a", weight: 4, pattern: ["XX", "X."]),
        PieceDefinition(id: "elbow-b", weight: 4, pattern: ["XX", ".X"]),
        PieceDefinition(id: "elbow-c", weight: 4, pattern: ["X.", "XX"]),
        PieceDefinition(id: "elbow-d", weight: 4, pattern: [".X", "XX"]),
        // 4 cells
        PieceDefinition(id: "quad-h", weight: 5, pattern: ["XXXX"]),
        PieceDefinition(id: "quad-v", weight: 5, pattern: ["X", "X", "X", "X"]),
        PieceDefinition(id: "square", weight: 7, pattern: ["XX", "XX"]),
        PieceDefinition(id: "tee-down", weight: 3, pattern: ["XXX", ".X."]),
        PieceDefinition(id: "tee-up", weight: 3, pattern: [".X.", "XXX"]),
        PieceDefinition(id: "tee-right", weight: 3, pattern: ["X.", "XX", "X."]),
        PieceDefinition(id: "tee-left", weight: 3, pattern: [".X", "XX", ".X"]),
        PieceDefinition(id: "hook-a", weight: 2, pattern: ["X.", "X.", "XX"]),
        PieceDefinition(id: "hook-b", weight: 2, pattern: [".X", ".X", "XX"]),
        PieceDefinition(id: "hook-c", weight: 2, pattern: ["XX", "X.", "X."]),
        PieceDefinition(id: "hook-d", weight: 2, pattern: ["XX", ".X", ".X"]),
        PieceDefinition(id: "hook-e", weight: 2, pattern: ["XXX", "X.."]),
        PieceDefinition(id: "hook-f", weight: 2, pattern: ["XXX", "..X"]),
        PieceDefinition(id: "hook-g", weight: 2, pattern: ["X..", "XXX"]),
        PieceDefinition(id: "hook-h", weight: 2, pattern: ["..X", "XXX"]),
        PieceDefinition(id: "zig-h", weight: 2, pattern: ["XX.", ".XX"]),
        PieceDefinition(id: "zag-h", weight: 2, pattern: [".XX", "XX."]),
        PieceDefinition(id: "zig-v", weight: 2, pattern: ["X.", "XX", ".X"]),
        PieceDefinition(id: "zag-v", weight: 2, pattern: [".X", "XX", "X."]),
        // 5 cells
        PieceDefinition(id: "beam-h", weight: 3, pattern: ["XXXXX"]),
        PieceDefinition(id: "beam-v", weight: 3, pattern: ["X", "X", "X", "X", "X"]),
        PieceDefinition(id: "corner-a", weight: 2, pattern: ["XXX", "X..", "X.."]),
        PieceDefinition(id: "corner-b", weight: 2, pattern: ["XXX", "..X", "..X"]),
        PieceDefinition(id: "corner-c", weight: 2, pattern: ["X..", "X..", "XXX"]),
        PieceDefinition(id: "corner-d", weight: 2, pattern: ["..X", "..X", "XXX"]),
    ].filter { $0.weight > 0 }

    /// Looks up a definition by ID in the given catalogue.
    public static func definition(id: String, in catalog: [PieceDefinition]) -> PieceDefinition? {
        catalog.first { $0.id == id }
    }
}
