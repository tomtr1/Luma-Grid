import XCTest
@testable import LumaGridEngine

final class LineClearAndScoringTests: XCTestCase {
    private let rules = ScoringRules.standard

    // 5. Completing and clearing one row
    func testCompletingARowClearsOnlyThatRow() throws {
        var rows = emptyRows()
        rows[8] = "XXXXXXX.."
        rows[7] = "X........"
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["XX"]), piece(["X"], id: 2), nil], seed: 1)

        let outcome = try session.place(slot: 0, at: GridPoint(row: 8, column: 7))

        XCTAssertEqual(outcome.clearedRows, [8])
        XCTAssertEqual(outcome.clearedColumns, [])
        XCTAssertEqual(outcome.clearedCells.count, 9)
        XCTAssertEqual(session.board.occupiedCount, 1, "Row 7 tile must remain")
        XCTAssertNotNil(session.board[7, 0])
        XCTAssertEqual(session.linesCleared, 1)
        // The pre-clear snapshot keeps the full row for animation.
        XCTAssertTrue(outcome.boardBeforeClear.isRowComplete(8))
    }

    // 6. Completing and clearing one column
    func testCompletingAColumnClearsOnlyThatColumn() throws {
        let rows = (0..<9).map { $0 < 6 ? "..X......" : "........." }
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["X", "X", "X"]), piece(["X"], id: 2), nil], seed: 1)

        let outcome = try session.place(slot: 0, at: GridPoint(row: 6, column: 2))

        XCTAssertEqual(outcome.clearedColumns, [2])
        XCTAssertEqual(outcome.clearedRows, [])
        XCTAssertTrue(session.board.isCompletelyEmpty)
    }

    // 7 & 8. Row and column from the same placement, intersection cleared once
    func testRowAndColumnClearedTogetherAndIntersectionCountedOnce() throws {
        // Row 4 is full except (4,4); column 4 is full except (4,4).
        var rows = emptyRows().map(Array.init)
        for i in 0..<9 where i != 4 {
            rows[4][i] = "X"
            rows[i][4] = "X"
        }
        rows[0][0] = "X" // a bystander tile
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows.map { String($0) }), tray: [piece(["X"]), piece(["X"], id: 2), nil], seed: 1)

        let outcome = try session.place(slot: 0, at: GridPoint(row: 4, column: 4))

        XCTAssertEqual(outcome.clearedRows, [4])
        XCTAssertEqual(outcome.clearedColumns, [4])
        XCTAssertEqual(outcome.linesCleared, 2)
        XCTAssertEqual(outcome.clearedCells.count, 17, "9 + 9 − 1 shared intersection")
        XCTAssertEqual(session.board.occupiedCount, 1)
        XCTAssertNotNil(session.board[0, 0])
        // Both lines are scored: 1 cell placed + 10 × 2² = 41.
        XCTAssertEqual(outcome.score, ScoreBreakdown(placementPoints: 1, linePoints: 40, comboBonus: 0))
        XCTAssertEqual(session.score, 41)
    }

    func testMultipleParallelRowsClearTogether() throws {
        var rows = emptyRows()
        rows[0] = "XXXXXXXX."
        rows[1] = "XXXXXXXX."
        rows[2] = "XXXXXXXX."
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["X", "X", "X"]), piece(["X"], id: 2), nil], seed: 1)
        let outcome = try session.place(slot: 0, at: GridPoint(row: 0, column: 8))
        XCTAssertEqual(outcome.clearedRows, [0, 1, 2])
        XCTAssertEqual(outcome.score.linePoints, 90)
        XCTAssertTrue(session.board.isCompletelyEmpty)
    }

    // 9. Score calculation for basic placement and line clear
    func testScoreFormula() {
        XCTAssertEqual(ScoreCalculator.score(cellsPlaced: 4, linesCleared: 0, comboStreak: 0, rules: rules).total, 4)
        XCTAssertEqual(ScoreCalculator.score(cellsPlaced: 2, linesCleared: 1, comboStreak: 1, rules: rules).total, 12)
        XCTAssertEqual(ScoreCalculator.score(cellsPlaced: 3, linesCleared: 3, comboStreak: 1, rules: rules).total, 93)
        XCTAssertEqual(ScoreCalculator.score(cellsPlaced: 1, linesCleared: 1, comboStreak: 3, rules: rules),
                       ScoreBreakdown(placementPoints: 1, linePoints: 10, comboBonus: 30))
        // No line clear means no combo bonus even if a stale streak is passed in.
        XCTAssertEqual(ScoreCalculator.score(cellsPlaced: 1, linesCleared: 0, comboStreak: 5, rules: rules).comboBonus, 0)
    }

    func testPlacementWithoutClearScoresCellsOnly() throws {
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(emptyRows()), tray: [piece(["XXX", "X.."]), piece(["X"], id: 2), nil], seed: 1)
        let outcome = try session.place(slot: 0, at: .init(row: 0, column: 0))
        XCTAssertEqual(outcome.score.total, 4)
        XCTAssertEqual(session.score, 4)
    }

    // 10. Combo progression and reset
    func testComboBuildsOnConsecutiveClearsAndResetsOnMiss() throws {
        var rows = emptyRows()
        rows[0] = "XXXXXXXX."
        rows[1] = "XXXXXXXX."
        let tray: [PieceInstance?] = [piece(["X"], id: 1), piece(["X"], id: 2), piece(["X"], id: 3)]
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: tray, seed: 1)

        let first = try session.place(slot: 0, at: .init(row: 0, column: 8))
        XCTAssertEqual(first.comboStreak, 1)
        XCTAssertFalse(first.isCombo)
        XCTAssertEqual(first.score.comboBonus, 0)

        let second = try session.place(slot: 1, at: .init(row: 1, column: 8))
        XCTAssertEqual(second.comboStreak, 2)
        XCTAssertTrue(second.isCombo)
        XCTAssertEqual(second.score.comboBonus, rules.comboBonusPerStep)

        let miss = try session.place(slot: 2, at: .init(row: 5, column: 5))
        XCTAssertEqual(miss.comboStreak, 0)
        XCTAssertEqual(session.comboStreak, 0)
        XCTAssertEqual(session.bestComboStreak, 2)
        XCTAssertEqual(session.score, 11 + (1 + 10 + 15) + 1)
    }
}
