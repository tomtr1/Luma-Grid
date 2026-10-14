@testable import LumaGridEngine

/// Builds a board from rows of characters: "." empty, "X" tile, "P" Prism tile.
func makeBoard(_ rows: [String]) -> BoardState {
    var board = BoardState(size: rows.count)
    for (row, line) in rows.enumerated() {
        precondition(line.count == rows.count, "Board rows must be square")
        for (column, character) in line.enumerated() {
            switch character {
            case "X": board[row, column] = Tile(colorIndex: 0)
            case "P": board[row, column] = Tile(colorIndex: 0, isPrism: true)
            default: break
            }
        }
    }
    return board
}

func emptyRows(_ size: Int = 9) -> [String] {
    Array(repeating: String(repeating: ".", count: size), count: size)
}

func piece(_ pattern: [String], id: Int = 100, prismCellIndex: Int? = nil) -> PieceInstance {
    PieceInstance(
        id: id,
        definition: PieceDefinition(id: "test-\(id)", weight: 1, pattern: pattern),
        colorIndex: 1,
        prismCellIndex: prismCellIndex
    )
}

/// A configuration whose generator never redraws, keeping refill behaviour obvious in tests.
let plainConfiguration: GameConfiguration = {
    var configuration = GameConfiguration.standard
    configuration.generation.playableTrayAttempts = 0
    return configuration
}()
