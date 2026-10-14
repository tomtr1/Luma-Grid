import XCTest
@testable import LumaGridEngine

final class BoardAndPlacementTests: XCTestCase {
    // 1. Empty board initialization
    func testNewSessionStartsWithEmptyNineByNineBoardAndThreePieces() {
        let session = GameSession(seed: 42)
        XCTAssertEqual(session.board.size, 9)
        XCTAssertTrue(session.board.isCompletelyEmpty)
        XCTAssertEqual(session.board.allPoints.count, 81)
        XCTAssertEqual(session.tray.remainingPieces.count, 3)
        XCTAssertEqual(session.score, 0)
        XCTAssertEqual(session.lumenCharge, 0)
        XCTAssertEqual(session.phase, .playing)
    }

    // 2. Legal placement
    func testLegalPlacementWritesTilesAndRemovesPieceFromTray() throws {
        let square = piece(["XX", "XX"])
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(emptyRows()), tray: [square, piece(["X"], id: 2), nil], seed: 1)

        let outcome = try session.place(slot: 0, at: GridPoint(row: 3, column: 4))

        XCTAssertEqual(Set(outcome.placedCells), [GridPoint(row: 3, column: 4), GridPoint(row: 3, column: 5),
                                                  GridPoint(row: 4, column: 4), GridPoint(row: 4, column: 5)])
        for point in outcome.placedCells { XCTAssertNotNil(session.board[point]) }
        XCTAssertEqual(session.board.occupiedCount, 4)
        XCTAssertNil(session.tray.piece(inSlot: 0))
        XCTAssertEqual(session.placements, 1)
    }

    // 3. Invalid placement outside each board edge
    func testPlacementOutsideEachEdgeIsRejectedWithoutChangingState() {
        let bar = piece(["XXX"])
        let column = piece(["X", "X", "X"], id: 2)
        let session = GameSession(configuration: plainConfiguration, board: makeBoard(emptyRows()), tray: [bar, column, nil], seed: 1)

        let attempts: [(Int, GridPoint)] = [
            (0, GridPoint(row: 0, column: -1)), // left
            (0, GridPoint(row: 0, column: 7)),  // right (needs columns 7...9)
            (1, GridPoint(row: -1, column: 0)), // top
            (1, GridPoint(row: 7, column: 0)),  // bottom (needs rows 7...9)
        ]
        for (slot, origin) in attempts {
            var copy = session
            XCTAssertFalse(copy.canPlace(slot: slot, at: origin), "origin \(origin)")
            XCTAssertThrowsError(try copy.place(slot: slot, at: origin)) { error in
                XCTAssertEqual(error as? PlacementError, .illegalPosition)
            }
            XCTAssertEqual(copy, session, "A rejected move must not change the session")
        }
        // The last legal positions along each edge succeed.
        XCTAssertTrue(session.canPlace(slot: 0, at: GridPoint(row: 8, column: 6)))
        XCTAssertTrue(session.canPlace(slot: 1, at: GridPoint(row: 6, column: 8)))
    }

    // 4. Collision with an occupied cell
    func testPlacementOverlappingAnOccupiedCellIsRejected() {
        var rows = emptyRows()
        rows[4] = "....X...."
        let session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["XX"]), nil, nil], seed: 1)
        var copy = session
        XCTAssertThrowsError(try copy.place(slot: 0, at: GridPoint(row: 4, column: 3)))
        XCTAssertEqual(copy, session)
        XCTAssertTrue(session.canPlace(slot: 0, at: GridPoint(row: 4, column: 5)))
    }

    func testPlacingFromAnEmptySlotIsRejected() {
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(emptyRows()), tray: [nil, piece(["X"]), nil], seed: 1)
        XCTAssertThrowsError(try session.place(slot: 0, at: GridPoint(row: 0, column: 0))) { error in
            XCTAssertEqual(error as? PlacementError, .emptySlot)
        }
        XCTAssertThrowsError(try session.place(slot: 7, at: GridPoint(row: 0, column: 0)))
    }

    func testLegalOriginsMatchCanPlaceForEveryCandidate() {
        var rows = emptyRows()
        rows[0] = "XXXX.XXXX"
        rows[1] = "XXXX.XXXX"
        let board = makeBoard(rows)
        let tall = piece(["X", "X"])
        let origins = board.legalOrigins(for: tall)
        for point in board.allPoints {
            XCTAssertEqual(origins.contains(point), board.canPlace(tall, at: point), "\(point)")
        }
        XCTAssertTrue(origins.contains(GridPoint(row: 0, column: 4)))
    }

    func testCatalogueShapesAreConnectedAndBetweenOneAndFiveCells() {
        let ids = PieceCatalog.standard.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "IDs must be unique")
        for definition in PieceCatalog.standard {
            XCTAssertTrue((1...5).contains(definition.cells.count), definition.id)
            XCTAssertTrue(definition.isOrthogonallyConnected, definition.id)
            XCTAssertGreaterThan(definition.weight, 0, definition.id)
        }
        let shapes = PieceCatalog.standard.map { Set($0.cells) }
        XCTAssertEqual(shapes.count, Set(shapes).count, "No duplicate shapes")
    }
}
