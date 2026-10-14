/// A row/column coordinate. Row 0 is the top of the board, column 0 is the left.
public struct GridPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
        GridPoint(row: lhs.row + rhs.row, column: lhs.column + rhs.column)
    }

    public var description: String { "(\(row),\(column))" }
}

/// A tile that occupies a board cell.
public struct Tile: Hashable, Codable, Sendable {
    /// Index into the active theme's tile palette. The engine never deals in actual colors.
    public var colorIndex: Int
    /// Prism Cells charge the Lumen meter when cleared as part of a completed line.
    public var isPrism: Bool

    public init(colorIndex: Int, isPrism: Bool = false) {
        self.colorIndex = colorIndex
        self.isPrism = isPrism
    }
}

/// A square grid of optional tiles. Value type: copying a board is cheap and safe.
public struct BoardState: Hashable, Codable, Sendable {
    public let size: Int
    private var cells: [Tile?]

    public init(size: Int) {
        precondition(size > 0, "Board size must be positive")
        self.size = size
        self.cells = Array(repeating: nil, count: size * size)
    }

    // MARK: Access

    public func contains(_ point: GridPoint) -> Bool {
        point.row >= 0 && point.row < size && point.column >= 0 && point.column < size
    }

    public subscript(point: GridPoint) -> Tile? {
        get {
            precondition(contains(point), "Point \(point) is outside the board")
            return cells[point.row * size + point.column]
        }
        set {
            precondition(contains(point), "Point \(point) is outside the board")
            cells[point.row * size + point.column] = newValue
        }
    }

    public subscript(row: Int, column: Int) -> Tile? {
        get { self[GridPoint(row: row, column: column)] }
        set { self[GridPoint(row: row, column: column)] = newValue }
    }

    public func isEmpty(_ point: GridPoint) -> Bool {
        contains(point) && self[point] == nil
    }

    public var occupiedCount: Int { cells.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }
    public var isCompletelyEmpty: Bool { occupiedCount == 0 }

    /// Every coordinate on the board in row-major order.
    public var allPoints: [GridPoint] {
        (0..<size).flatMap { row in (0..<size).map { GridPoint(row: row, column: $0) } }
    }

    // MARK: Lines

    public func isRowComplete(_ row: Int) -> Bool {
        (0..<size).allSatisfy { self[row, $0] != nil }
    }

    public func isColumnComplete(_ column: Int) -> Bool {
        (0..<size).allSatisfy { self[$0, column] != nil }
    }

    public var completedRows: [Int] { (0..<size).filter(isRowComplete) }
    public var completedColumns: [Int] { (0..<size).filter(isColumnComplete) }

    // MARK: Placement

    /// True when every cell of `piece`, offset by `origin`, is on the board and empty.
    public func canPlace(_ piece: PieceInstance, at origin: GridPoint) -> Bool {
        piece.cells.allSatisfy { isEmpty(origin + $0) }
    }

    /// Every origin where `piece` fits. The origin is the top-left of the piece's bounding box.
    public func legalOrigins(for piece: PieceInstance) -> [GridPoint] {
        guard piece.width <= size, piece.height <= size else { return [] }
        var result: [GridPoint] = []
        for row in 0...(size - piece.height) {
            for column in 0...(size - piece.width) {
                let origin = GridPoint(row: row, column: column)
                if canPlace(piece, at: origin) { result.append(origin) }
            }
        }
        return result
    }

    /// Faster variant of `!legalOrigins(for:).isEmpty` that stops at the first legal origin.
    public func hasLegalPlacement(for piece: PieceInstance) -> Bool {
        guard piece.width <= size, piece.height <= size else { return false }
        for row in 0...(size - piece.height) {
            for column in 0...(size - piece.width)
            where canPlace(piece, at: GridPoint(row: row, column: column)) {
                return true
            }
        }
        return false
    }
}
