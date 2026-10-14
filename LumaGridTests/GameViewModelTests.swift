import XCTest
import LumaGridEngine
import LumaGridServices
@testable import LumaGrid

/// View-model orchestration tests (iOS Simulator only). Rules themselves are covered by the
/// LumaGridCore package tests, which also run on Linux.
@MainActor
final class GameViewModelTests: XCTestCase {
    private func makeApp() -> AppModel {
        let app = AppModel.preview()
        app.progress.update { $0.tutorialCompleted = true }
        return app
    }

    private func piece(_ pattern: [String], id: Int) -> PieceInstance {
        PieceInstance(id: id, definition: PieceDefinition(id: "t\(id)", weight: 1, pattern: pattern), colorIndex: 0)
    }

    func testTapToPlaceAppliesMoveAndSavesSession() {
        let app = makeApp()
        let session = GameSession(board: BoardState(size: 9), tray: [piece(["XX"], id: 1), piece(["X"], id: 2), nil], seed: 1)
        let game = GameViewModel(session: session, app: app)
        game.reduceMotion = true

        game.tapSlot(0)
        XCTAssertEqual(game.selectedSlot, 0)
        game.tapCell(GridPoint(row: 4, column: 4))

        XCTAssertNil(game.selectedSlot)
        XCTAssertEqual(game.session.board.occupiedCount, 2)
        XCTAssertEqual(game.displayBoard, game.session.board)
        XCTAssertEqual(app.progress.progress.savedGame, game.session)
    }

    func testInvalidTapLeavesStateUnchanged() {
        let app = makeApp()
        let session = GameSession(board: BoardState(size: 9), tray: [piece(["XXX"], id: 1), piece(["X"], id: 2), nil], seed: 1)
        let game = GameViewModel(session: session, app: app)
        game.tapSlot(0)
        game.tapCell(GridPoint(row: 0, column: 8)) // would overflow the right edge
        XCTAssertEqual(game.session, session)
        XCTAssertEqual(game.hint, .doesNotFit)
    }

    func testGameOverRecordsResultCoinsAndAdPacing() {
        let app = makeApp()
        var rows = (0..<9).map { row in String((0..<9).map { column in (row + column) % 2 == 0 ? "X" : "." }) }
        rows[8] = "X.X.X.X.."
        var board = BoardState(size: 9)
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() where ch == "X" { board[r, c] = Tile(colorIndex: 0) }
        }
        let session = GameSession(board: board, tray: [piece(["XX"], id: 1), piece(["XX"], id: 2), nil], seed: 1)
        let game = GameViewModel(session: session, app: app)
        game.reduceMotion = true

        game.tapSlot(0)
        game.tapCell(GridPoint(row: 8, column: 7))

        let result = try? XCTUnwrap(game.result)
        XCTAssertNotNil(result)
        XCTAssertEqual(app.progress.progress.stats.gamesPlayed, 1)
        XCTAssertEqual(app.progress.progress.coins, result?.coinsEarned)
        XCTAssertEqual(app.progress.progress.adPacing.completedGames, 1)
        XCTAssertNil(app.progress.progress.savedGame)
    }
}
