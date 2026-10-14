import XCTest
@testable import LumaGridEngine

final class RewardTests: XCTestCase {
    // 20. Coin reward calculation
    func testRoundRewardFormula() {
        let economy = EconomyConfiguration.standard
        XCTAssertEqual(RoundRewardCalculator.coins(forScore: 0, mode: .classic, economy: economy), 5)
        XCTAssertEqual(RoundRewardCalculator.coins(forScore: 99, mode: .classic, economy: economy), 5)
        XCTAssertEqual(RoundRewardCalculator.coins(forScore: 100, mode: .classic, economy: economy), 6)
        XCTAssertEqual(RoundRewardCalculator.coins(forScore: 1_250, mode: .classic, economy: economy), 17)
        XCTAssertEqual(RoundRewardCalculator.coins(forScore: 1_000_000, mode: .classic, economy: economy), 40, "capped")
        XCTAssertEqual(RoundRewardCalculator.coins(forScore: -5, mode: .classic, economy: economy), 5)
    }

    func testMakeResultReportsStatsAndBest() throws {
        var rows = emptyRows()
        rows[0] = "XXXXXXXX."
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows), tray: [piece(["X"]), piece(["X"], id: 2), nil], seed: 3)
        try session.place(slot: 0, at: .init(row: 0, column: 8))
        let result = session.makeResult(previousBestScore: 5, economy: .standard)
        XCTAssertEqual(result.score, 11)
        XCTAssertTrue(result.isNewBest)
        XCTAssertEqual(result.bestScore, 11)
        XCTAssertEqual(result.linesCleared, 1)
        XCTAssertEqual(result.bestComboStreak, 1)
        XCTAssertEqual(result.coinsEarned, 5)

        let notBest = session.makeResult(previousBestScore: 500, economy: .standard)
        XCTAssertFalse(notBest.isNewBest)
        XCTAssertEqual(notBest.bestScore, 500)
    }
}
