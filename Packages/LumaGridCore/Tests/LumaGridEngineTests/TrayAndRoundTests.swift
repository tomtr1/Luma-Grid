import XCTest
@testable import LumaGridEngine

final class TrayAndRoundTests: XCTestCase {
    // 16. Tray refill only after all three pieces are used
    func testTrayRefillsOnlyAfterAllPiecesArePlaced() throws {
        var session = GameSession(configuration: plainConfiguration, seed: 7)
        let originalIDs = session.tray.remainingPieces.map(\.id)
        XCTAssertEqual(originalIDs.count, 3)

        for (index, slot) in [2, 0, 1].enumerated() {
            let piece = try XCTUnwrap(session.tray.piece(inSlot: slot))
            let origin = try XCTUnwrap(session.board.legalOrigins(for: piece).first)
            let outcome = try session.place(slot: slot, at: origin)
            if index < 2 {
                XCTAssertFalse(outcome.trayRefilled)
                XCTAssertEqual(session.tray.remainingPieces.count, 2 - index)
            } else {
                XCTAssertTrue(outcome.trayRefilled)
                XCTAssertEqual(session.tray.remainingPieces.count, 3)
                XCTAssertTrue(Set(session.tray.remainingPieces.map(\.id)).isDisjoint(with: originalIDs))
            }
        }
    }

    // 17. Game over when no remaining piece can fit
    func testGameOverWhenNoRemainingPieceFits() throws {
        // Checkerboard-ish board: no two horizontally or vertically adjacent empty cells.
        let rows = (0..<9).map { row in
            String((0..<9).map { column in (row + column) % 2 == 0 ? "X" : "." })
        }
        let session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["XX"]), piece(["X", "X"], id: 2), nil], seed: 1)
        XCTAssertFalse(session.hasAnyLegalPlacement)
        XCTAssertTrue(session.isGameOver)

        var copy = session
        XCTAssertThrowsError(try copy.place(slot: 0, at: .init(row: 0, column: 1))) { error in
            XCTAssertEqual(error as? PlacementError, .gameIsOver)
        }
    }

    func testPlacementThatLeavesNoMovesEndsTheRound() throws {
        var rows = (0..<9).map { row in
            String((0..<9).map { column in (row + column) % 2 == 0 ? "X" : "." })
        }
        rows[8] = "X.X.X.X.." // (8,7) and (8,8) empty: room for exactly one domino
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["XX"]), piece(["XX"], id: 2), nil], seed: 1)
        XCTAssertFalse(session.isGameOver)
        let outcome = try session.place(slot: 0, at: .init(row: 8, column: 7))
        XCTAssertTrue(outcome.isGameOver)
        XCTAssertTrue(session.isGameOver)
    }

    // 18. No false game over when at least one valid placement exists
    func testNoGameOverWhileOnePieceStillFits() {
        let rows = (0..<9).map { row in
            String((0..<9).map { column in (row + column) % 2 == 0 ? "X" : "." })
        }
        // The domino cannot fit but the single dot can.
        let session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["XX"]), nil, piece(["X"], id: 3)], seed: 1)
        XCTAssertTrue(session.hasAnyLegalPlacement)
        XCTAssertFalse(session.isGameOver)
    }

    func testStuckWithPulseReadyIsNotGameOverUntilPulseIsSpent() throws {
        let rows = (0..<9).map { row in
            String((0..<9).map { column in (row + column) % 2 == 0 ? "X" : "." })
        }
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [piece(["XXX", "XXX", "XXX"]), nil, nil], seed: 1, lumenCharge: 3)
        XCTAssertFalse(session.isGameOver)
        XCTAssertTrue(session.needsPulseToContinue)

        // Pulse opens a 3×3 hole, so the 3×3 block fits and the round continues.
        let outcome = try session.activatePulse(at: .init(row: 4, column: 4))
        XCTAssertFalse(outcome.isGameOver)
        XCTAssertTrue(session.canPlace(slot: 0, at: .init(row: 3, column: 3)))
    }

    func testPulseThatDoesNotOpenRoomEndsTheRound() throws {
        let rows = (0..<9).map { row in
            String((0..<9).map { column in (row + column) % 2 == 0 ? "X" : "." })
        }
        // Pulse opens a 3×3 hole (plus the checkerboard gaps around it); a 4×4 block still cannot fit.
        let big = piece(["XXXX", "XXXX", "XXXX", "XXXX"])
        var session = GameSession(configuration: plainConfiguration, board: makeBoard(rows),
                                  tray: [big, nil, nil], seed: 1, lumenCharge: 3)
        let outcome = try session.activatePulse(at: .init(row: 4, column: 4))
        XCTAssertTrue(outcome.isGameOver)
    }

    // 19. Seeded piece generation reproducibility
    func testSameSeedProducesSameTrays() throws {
        func playSome(seed: UInt64) throws -> [String] {
            var session = GameSession(seed: seed)
            var log: [String] = []
            for _ in 0..<12 {
                guard !session.isGameOver else { break }
                log.append(session.tray.slots.map { $0.map { "\($0.definitionID):\($0.colorIndex):\(String(describing: $0.prismCellIndex))" } ?? "-" }.joined(separator: ","))
                let (slot, origin) = try XCTUnwrap(firstLegalMove(in: session))
                try session.place(slot: slot, at: origin)
            }
            return log
        }
        XCTAssertEqual(try playSome(seed: 1234), try playSome(seed: 1234))
        XCTAssertNotEqual(try playSome(seed: 1234), try playSome(seed: 4321))
    }

    func testRandomSourceIsStableAcrossPlatforms() {
        // Pinned values guard against accidental changes to the generator algorithm,
        // which would silently change every daily puzzle.
        var random = SplitMix64(seed: 0)
        XCTAssertEqual(random.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(random.next(), 0x6E78_9E6A_A1B9_65F4)
    }

    func testGeneratorRespectsPrismLimitPerTray() {
        var configuration = GameConfiguration.standard
        configuration.generation.prismChance = 1.0
        configuration.generation.maxPrismPiecesPerTray = 1
        var generator = PieceGenerator(seed: 99)
        for _ in 0..<50 {
            let tray = generator.makeTray(for: BoardState(size: 9), configuration: configuration)
            XCTAssertEqual(tray.filter(\.hasPrism).count, 1)
        }
    }

    func testGeneratedPieceIDsAreUnique() {
        var generator = PieceGenerator(seed: 5)
        var ids: Set<Int> = []
        for _ in 0..<30 {
            for piece in generator.makeTray(for: BoardState(size: 9), configuration: .standard) {
                XCTAssertTrue(ids.insert(piece.id).inserted)
            }
        }
    }

    func testSessionRoundTripsThroughCodableAndContinuesIdentically() throws {
        var session = GameSession(seed: 2024)
        let (slot, origin) = try XCTUnwrap(firstLegalMove(in: session))
        try session.place(slot: slot, at: origin)

        let data = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(GameSession.self, from: data)
        XCTAssertEqual(restored, session)

        // Both continue to deal exactly the same future pieces.
        for _ in 0..<6 {
            guard let move = firstLegalMove(in: session) else { break }
            let a = try session.place(slot: move.0, at: move.1)
            let b = try restored.place(slot: move.0, at: move.1)
            XCTAssertEqual(a, b)
        }
        XCTAssertEqual(restored, session)
    }

    func testDailySeedIsDeterministicPerDate() {
        let a = DailyChallenge.makeSession(dateKey: DailyChallenge.dateKey(year: 2026, month: 3, day: 7))
        let b = DailyChallenge.makeSession(dateKey: "2026-03-07")
        let c = DailyChallenge.makeSession(dateKey: "2026-03-08")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.tray, c.tray)
        XCTAssertEqual(a.mode, .daily(dateKey: "2026-03-07"))
    }

    // A full automated game must always terminate in a game over without crashing.
    func testAutomatedGamesReachGameOver() throws {
        for seed in UInt64(1)...20 {
            var session = GameSession(seed: seed)
            var moves = 0
            while !session.isGameOver, moves < 2_000 {
                if let (slot, origin) = firstLegalMove(in: session) {
                    try session.place(slot: slot, at: origin)
                } else if session.needsPulseToContinue {
                    let target = try XCTUnwrap(session.board.allPoints.first { session.board[$0] != nil })
                    try session.activatePulse(at: target)
                }
                moves += 1
            }
            XCTAssertTrue(session.isGameOver, "seed \(seed) did not finish")
            XCTAssertGreaterThan(session.score, 0)
        }
    }
}

/// Picks a deterministic legal move: first slot with a legal origin, preferring the bottom-right
/// so automated games fill the board and eventually end.
func firstLegalMove(in session: GameSession) -> (Int, GridPoint)? {
    for (slot, piece) in session.tray.slots.enumerated() {
        guard let piece else { continue }
        if let origin = session.board.legalOrigins(for: piece).last { return (slot, origin) }
    }
    return nil
}
