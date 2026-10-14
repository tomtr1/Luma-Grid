import XCTest
@testable import LumaGridEngine

final class LumenPulseTests: XCTestCase {
    // 11. Prism Cell charging when a cleared line contains it
    func testClearingALineContainingAPrismChargesTheMeter() throws {
        var rows = emptyRows()
        rows[2] = "XXXPXXXX."
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["X"]), piece(["X"], id: 2), nil], seed: 1)
        let outcome = try session.place(slot: 0, at: .init(row: 2, column: 8))
        XCTAssertTrue(outcome.lumenCharged)
        XCTAssertEqual(session.lumenCharge, 1)
    }

    func testPrismPlacedInTheClearingPieceAlsoCharges() throws {
        var rows = emptyRows()
        rows[2] = "XXXXXXXX."
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"], prismCellIndex: 0), piece(["X"], id: 2), nil], seed: 1)
        try session.place(slot: 0, at: .init(row: 2, column: 8))
        XCTAssertEqual(session.lumenCharge, 1)
    }

    func testPrismOutsideClearedLinesDoesNotCharge() throws {
        var rows = emptyRows()
        rows[2] = "XXXXXXXX."
        rows[5] = "P........"
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["X"]), piece(["X"], id: 2), nil], seed: 1)
        let outcome = try session.place(slot: 0, at: .init(row: 2, column: 8))
        XCTAssertFalse(outcome.lumenCharged)
        XCTAssertEqual(session.lumenCharge, 0)
        XCTAssertEqual(session.board[5, 0]?.isPrism, true, "Uncleared prism stays on the board")
    }

    // 12. No double counting when one move clears a row and column through the prism,
    //     or clears several lines with several prisms.
    func testOnePlacementChargesAtMostOnce() throws {
        var grid = emptyRows().map(Array.init)
        for i in 0..<9 where i != 4 {
            grid[4][i] = "X"
            grid[i][4] = "X"
        }
        grid[4][0] = "P" // prism in the row
        grid[0][4] = "P" // prism in the column
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(grid.map { String($0) }),
                                  tray: [piece(["X"], prismCellIndex: 0), piece(["X"], id: 2), nil], seed: 1)
        let outcome = try session.place(slot: 0, at: .init(row: 4, column: 4))
        XCTAssertEqual(outcome.linesCleared, 2)
        XCTAssertEqual(session.lumenCharge, 1)
    }

    func testChargeIsCappedAtPulseRequirement() throws {
        var rows = emptyRows()
        rows[0] = "PXXXXXXX."
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"]), piece(["X"], id: 2), nil], seed: 1, lumenCharge: 3)
        let outcome = try session.place(slot: 0, at: .init(row: 0, column: 8))
        XCTAssertFalse(outcome.lumenCharged)
        XCTAssertFalse(outcome.pulseBecameReady)
        XCTAssertEqual(session.lumenCharge, 3)
    }

    func testThirdChargeMakesPulseReady() throws {
        var rows = emptyRows()
        rows[0] = "PXXXXXXX."
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"]), piece(["X"], id: 2), nil], seed: 1, lumenCharge: 2)
        XCTAssertFalse(session.isPulseReady)
        let outcome = try session.place(slot: 0, at: .init(row: 0, column: 8))
        XCTAssertTrue(outcome.pulseBecameReady)
        XCTAssertTrue(session.isPulseReady)
    }

    // 13. Pulse activation only when fully charged
    func testPulseRequiresFullCharge() {
        var rows = emptyRows()
        rows[4] = "...XXX..."
        for charge in 0..<3 {
            var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                      tray: [piece(["X"]), nil, nil], seed: 1, lumenCharge: charge)
            let before = session
            XCTAssertThrowsError(try session.activatePulse(at: .init(row: 4, column: 4))) { error in
                XCTAssertEqual(error as? PulseError, .notCharged)
            }
            XCTAssertEqual(session, before)
        }
    }

    // 14 & 15. Pulse clears only occupied cells in the 3×3 region and consumes the meter
    func testPulseClearsOnlyTheThreeByThreeAreaAndConsumesCharge() throws {
        let rows = [
            "XXXXX....",
            "XXXXX....",
            "XXXXX....",
            "XXXXX....",
            "XXXXX....",
            ".........",
            ".........",
            ".........",
            ".........",
        ]
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"]), nil, nil], seed: 1, lumenCharge: 3)
        let outcome = try session.activatePulse(at: .init(row: 2, column: 2))

        let expectedArea = Set((1...3).flatMap { r in (1...3).map { GridPoint(row: r, column: $0) } })
        XCTAssertEqual(Set(outcome.area), expectedArea)
        XCTAssertEqual(outcome.clearedCells, expectedArea)
        XCTAssertEqual(session.board.occupiedCount, 25 - 9)
        for point in expectedArea { XCTAssertNil(session.board[point]) }
        XCTAssertNotNil(session.board[0, 0])
        XCTAssertNotNil(session.board[4, 4])
        XCTAssertEqual(session.lumenCharge, 0)
        XCTAssertEqual(session.pulsesUsed, 1)
        XCTAssertFalse(session.isPulseReady)
    }

    func testPulseLeavesEmptyCellsEmptyAndClampsAtEdges() throws {
        var rows = emptyRows()
        rows[0] = "X.X......"
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"]), nil, nil], seed: 1, lumenCharge: 3)
        // Tapping the corner selects the 3×3 area anchored in that corner.
        let outcome = try session.activatePulse(at: .init(row: 0, column: 0))
        XCTAssertEqual(outcome.area.count, 9)
        XCTAssertEqual(Set(outcome.area.map(\.row)), [0, 1, 2])
        XCTAssertEqual(Set(outcome.area.map(\.column)), [0, 1, 2])
        XCTAssertEqual(outcome.clearedCells, [GridPoint(row: 0, column: 0), GridPoint(row: 0, column: 2)])
        XCTAssertTrue(session.board.isCompletelyEmpty)
    }

    func testPulseOnEmptyAreaIsRefusedAndKeepsCharge() {
        var rows = emptyRows()
        rows[0] = "X........"
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"]), nil, nil], seed: 1, lumenCharge: 3)
        XCTAssertThrowsError(try session.activatePulse(at: .init(row: 7, column: 7))) { error in
            XCTAssertEqual(error as? PulseError, .nothingToClear)
        }
        XCTAssertEqual(session.lumenCharge, 3)
    }

    func testPulseDoesNotChargeTheMeterEvenWhenItRemovesPrisms() throws {
        var rows = emptyRows()
        rows[0] = "PPP......"
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["X"]), nil, nil], seed: 1, lumenCharge: 3)
        try session.activatePulse(at: .init(row: 1, column: 1))
        XCTAssertEqual(session.lumenCharge, 0)
    }
}
