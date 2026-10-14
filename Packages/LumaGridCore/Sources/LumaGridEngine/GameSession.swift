public enum GameMode: Hashable, Codable, Sendable {
    case classic
    /// Deterministic puzzle for one calendar day. `dateKey` is "YYYY-MM-DD".
    case daily(dateKey: String)

    public var isDaily: Bool {
        if case .daily = self { return true }
        return false
    }
}

public enum GamePhase: Hashable, Codable, Sendable {
    case playing
    case gameOver
}

public enum PlacementError: Error, Hashable, Sendable {
    case gameIsOver
    case emptySlot
    case illegalPosition
}

public enum PulseError: Error, Hashable, Sendable {
    case gameIsOver
    case notCharged
    case outsideBoard
    /// The chosen area has no occupied cells; refusing avoids wasting the charge.
    case nothingToClear
}

/// The complete, already-decided result of one placement. The UI animates this; it never
/// re-derives rules on its own.
public struct PlacementOutcome: Hashable, Sendable {
    public let piece: PieceInstance
    public let slot: Int
    public let origin: GridPoint
    public let placedCells: [GridPoint]
    /// Board immediately after the piece lands and before lines are removed (for animation).
    public let boardBeforeClear: BoardState
    public let clearedRows: [Int]
    public let clearedColumns: [Int]
    /// Unique cells removed; an intersection of a cleared row and column appears once.
    public let clearedCells: Set<GridPoint>
    public let score: ScoreBreakdown
    public let comboStreak: Int
    public let lumenCharged: Bool
    public let pulseBecameReady: Bool
    public let trayRefilled: Bool
    public let isGameOver: Bool

    public var linesCleared: Int { clearedRows.count + clearedColumns.count }
    /// A combo is two or more consecutive line-clearing placements.
    public var isCombo: Bool { linesCleared > 0 && comboStreak >= 2 }
}

public struct PulseOutcome: Hashable, Sendable {
    public let area: [GridPoint]
    public let clearedCells: Set<GridPoint>
    public let isGameOver: Bool
}

/// One round of LumaGrid. All rules are applied here; every action is atomic: either it
/// throws without changing anything, or it applies the whole transition
/// (placement → line detection → clearing → scoring → Lumen → combo → tray → round state).
public struct GameSession: Hashable, Codable, Sendable {
    public let configuration: GameConfiguration
    public let mode: GameMode
    public private(set) var board: BoardState
    public private(set) var tray: PieceTrayState
    public private(set) var generator: PieceGenerator
    public private(set) var phase: GamePhase = .playing

    public private(set) var score = 0
    public private(set) var comboStreak = 0
    public private(set) var bestComboStreak = 0
    public private(set) var linesCleared = 0
    public private(set) var lumenCharge = 0
    public private(set) var pulsesUsed = 0
    public private(set) var placements = 0

    /// Starts a new round with an empty board and a freshly dealt tray.
    public init(configuration: GameConfiguration = .standard, mode: GameMode = .classic, seed: UInt64) {
        self.configuration = configuration
        self.mode = mode
        self.board = BoardState(size: configuration.boardSize)
        self.generator = PieceGenerator(seed: seed)
        let pieces = generator.makeTray(for: board, configuration: configuration)
        self.tray = PieceTrayState(pieces: pieces)
    }

    /// Builds a session from explicit state. Used by tests and tooling; normal resume uses Codable.
    public init(
        configuration: GameConfiguration = .standard,
        mode: GameMode = .classic,
        board: BoardState,
        tray: [PieceInstance?],
        seed: UInt64,
        lumenCharge: Int = 0,
        comboStreak: Int = 0
    ) {
        precondition(board.size == configuration.boardSize, "Board size must match configuration")
        self.configuration = configuration
        self.mode = mode
        self.board = board
        self.generator = PieceGenerator(seed: seed)
        self.lumenCharge = min(max(0, lumenCharge), configuration.lumen.chargesForPulse)
        self.comboStreak = comboStreak
        self.bestComboStreak = comboStreak
        // Empty slots are preserved exactly as given.
        self.tray = PieceTrayState(slots: tray)
        updatePhase()
    }

    // MARK: Queries

    public var isPulseReady: Bool { lumenCharge >= configuration.lumen.chargesForPulse }
    public var isGameOver: Bool { phase == .gameOver }

    public func canPlace(slot: Int, at origin: GridPoint) -> Bool {
        guard phase == .playing, let piece = tray.piece(inSlot: slot) else { return false }
        return board.canPlace(piece, at: origin)
    }

    /// True if at least one remaining tray piece fits somewhere.
    public var hasAnyLegalPlacement: Bool {
        tray.remainingPieces.contains(where: board.hasLegalPlacement(for:))
    }

    /// No piece fits but Pulse is ready: the player must use Pulse (the round is not over).
    public var needsPulseToContinue: Bool {
        phase == .playing && !hasAnyLegalPlacement && isPulseReady
    }

    /// The square area Pulse would clear for a tap at `center`, shifted to stay on the board.
    public func pulseArea(centeredAt center: GridPoint) -> [GridPoint] {
        let side = min(configuration.lumen.pulseAreaSide, board.size)
        let half = side / 2
        let top = min(max(0, center.row - half), board.size - side)
        let left = min(max(0, center.column - half), board.size - side)
        return (top..<(top + side)).flatMap { row in
            (left..<(left + side)).map { GridPoint(row: row, column: $0) }
        }
    }

    // MARK: Actions

    @discardableResult
    public mutating func place(slot: Int, at origin: GridPoint) throws -> PlacementOutcome {
        guard phase == .playing else { throw PlacementError.gameIsOver }
        guard let piece = tray.piece(inSlot: slot) else { throw PlacementError.emptySlot }
        guard board.canPlace(piece, at: origin) else { throw PlacementError.illegalPosition }

        // 1. Placement
        var newBoard = board
        let placedCells = piece.cells.map { origin + $0 }
        for (index, point) in placedCells.enumerated() {
            newBoard[point] = piece.tile(forCellAt: index)
        }
        let boardBeforeClear = newBoard

        // 2. Line detection
        let rows = newBoard.completedRows
        let columns = newBoard.completedColumns
        var cleared = Set<GridPoint>()
        for row in rows {
            for column in 0..<newBoard.size { cleared.insert(GridPoint(row: row, column: column)) }
        }
        for column in columns {
            for row in 0..<newBoard.size { cleared.insert(GridPoint(row: row, column: column)) }
        }

        // 3. Lumen: at most one charge per placement, regardless of how many prisms or lines.
        let clearedPrism = cleared.contains { newBoard[$0]?.isPrism == true }

        // 4. Clearing (a set, so intersections are removed exactly once)
        for point in cleared { newBoard[point] = nil }

        // 5. Combo and scoring
        let lineCount = rows.count + columns.count
        let newStreak = lineCount > 0 ? comboStreak + 1 : 0
        let breakdown = ScoreCalculator.score(
            cellsPlaced: placedCells.count,
            linesCleared: lineCount,
            comboStreak: newStreak,
            rules: configuration.scoring
        )

        let wasReady = isPulseReady
        let previousCharge = lumenCharge
        let newCharge = clearedPrism ? min(lumenCharge + 1, configuration.lumen.chargesForPulse) : lumenCharge

        // 6. Commit (nothing above can fail, so the transition is atomic)
        board = newBoard
        score += breakdown.total
        comboStreak = newStreak
        bestComboStreak = max(bestComboStreak, newStreak)
        linesCleared += lineCount
        lumenCharge = newCharge
        placements += 1
        tray.removePiece(inSlot: slot)

        // 7. Tray refill only once all pieces are used
        var refilled = false
        if tray.isEmpty {
            tray = PieceTrayState(pieces: generator.makeTray(for: board, configuration: configuration))
            refilled = true
        }

        // 8. Round state
        updatePhase()

        return PlacementOutcome(
            piece: piece,
            slot: slot,
            origin: origin,
            placedCells: placedCells,
            boardBeforeClear: boardBeforeClear,
            clearedRows: rows,
            clearedColumns: columns,
            clearedCells: cleared,
            score: breakdown,
            comboStreak: newStreak,
            lumenCharged: newCharge > previousCharge,
            pulseBecameReady: !wasReady && isPulseReady,
            trayRefilled: refilled,
            isGameOver: phase == .gameOver
        )
    }

    @discardableResult
    public mutating func activatePulse(at center: GridPoint) throws -> PulseOutcome {
        guard phase == .playing else { throw PulseError.gameIsOver }
        guard isPulseReady else { throw PulseError.notCharged }
        guard board.contains(center) else { throw PulseError.outsideBoard }

        let area = pulseArea(centeredAt: center)
        let occupied = Set(area.filter { board[$0] != nil })
        guard !occupied.isEmpty else { throw PulseError.nothingToClear }

        for point in occupied { board[point] = nil }
        lumenCharge = 0
        pulsesUsed += 1
        updatePhase()
        return PulseOutcome(area: area, clearedCells: occupied, isGameOver: phase == .gameOver)
    }

    // MARK: Results

    public func makeResult(previousBestScore: Int, economy: EconomyConfiguration) -> GameResult {
        GameResult(
            mode: mode,
            score: score,
            previousBestScore: previousBestScore,
            linesCleared: linesCleared,
            bestComboStreak: bestComboStreak,
            pulsesUsed: pulsesUsed,
            placements: placements,
            coinsEarned: RoundRewardCalculator.coins(forScore: score, mode: mode, economy: economy)
        )
    }

    // MARK: Private

    private mutating func updatePhase() {
        if phase == .playing, !hasAnyLegalPlacement, !isPulseReady {
            phase = .gameOver
        }
    }
}
