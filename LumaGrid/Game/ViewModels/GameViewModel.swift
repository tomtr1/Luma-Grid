import Foundation
import Observation
import SwiftUI
import LumaGridEngine
import LumaGridServices

/// Orchestrates one round on screen. The `GameSession` engine decides every outcome; this class
/// sequences presentation (ghost previews, clear animation, sounds, popups), persistence after
/// each move, and the end-of-round flow. It never re-implements game rules.
@MainActor
@Observable
final class GameViewModel {
    // MARK: Engine state

    private(set) var session: GameSession

    // MARK: Presentation state

    /// What the board currently shows. Equals `session.board`, except briefly while a clear animates.
    private(set) var displayBoard: BoardState
    private(set) var clearingCells: Set<GridPoint> = []
    /// True during the short clear animation; new moves wait for it (≤ ~0.25 s).
    private(set) var isResolving = false
    private(set) var drag: DragState?
    private(set) var selectedSlot: Int?
    private(set) var isPulseArmed = false
    private(set) var pulsePreviewCenter: GridPoint?
    private(set) var popup: ScorePopup?
    private(set) var hint: Hint?
    private(set) var result: GameResult?
    private(set) var payout: RoundPayout?
    private(set) var rewardedState: RewardedState = .idle
    var isPaused = false
    var isTutorialVisible: Bool

    // MARK: Layout (reported by views, in the "game" coordinate space)

    var boardFrame: CGRect = .zero
    var trayFrames: [Int: CGRect] = [:]
    var trayCellSize: CGFloat = 16
    var reduceMotion = false

    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private var popupTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    init(session: GameSession, app: AppModel) {
        self.session = session
        self.displayBoard = session.board
        self.app = app
        self.isTutorialVisible = !app.progress.progress.tutorialCompleted
        if session.needsPulseToContinue { showHint(.usePulse) }
    }

    /// Finger movement (points) below which a touch on a tray piece counts as a tap.
    static let tapSlop: CGFloat = 6

    // MARK: Derived

    var cellSize: CGFloat { boardFrame.width / CGFloat(session.board.size) }
    var mode: GameMode { session.mode }
    var bestScore: Int { max(app.progress.progress.previousBest(for: session.mode), session.score) }
    var isInteractive: Bool { result == nil && !isPaused && !isTutorialVisible && !isResolving }

    var ghostCells: [GridPoint] {
        guard let drag, !drag.isReturning, let origin = drag.origin, let piece = session.tray.piece(inSlot: drag.slot) else { return [] }
        return piece.cells.map { origin + $0 }
    }

    var pulsePreviewArea: Set<GridPoint> {
        guard isPulseArmed, let center = pulsePreviewCenter else { return [] }
        return Set(session.pulseArea(centeredAt: center))
    }

    // MARK: Drag & drop

    /// Called for every finger movement. The piece lifts only after a few points of movement,
    /// so a plain tap selects it instead (tap-to-place).
    func beginDrag(slot: Int, at location: CGPoint, translation: CGSize) {
        guard isInteractive, session.tray.piece(inSlot: slot) != nil, drag == nil || drag?.slot == slot else { return }
        if drag == nil, hypot(translation.width, translation.height) < Self.tapSlop { return }
        if drag == nil {
            app.feedback.prepare()
            app.feedback.play(.pickUp)
            isPulseArmed = false
            pulsePreviewCenter = nil
        }
        updateDrag(slot: slot, location: location)
    }

    func updateDrag(slot: Int, location: CGPoint) {
        guard let piece = session.tray.piece(inSlot: slot), cellSize > 0 else { return }
        let rect = draggedPieceRect(for: piece, fingerAt: location)
        let column = Int(((rect.minX - boardFrame.minX) / cellSize).rounded())
        let row = Int(((rect.minY - boardFrame.minY) / cellSize).rounded())
        let origin = GridPoint(row: row, column: column)
        let fitsOnBoard = piece.cells.allSatisfy { session.board.contains(origin + $0) }
        let isValid = fitsOnBoard && session.canPlace(slot: slot, at: origin)
        drag = DragState(slot: slot, location: location, origin: fitsOnBoard ? origin : nil, isValid: isValid)
    }

    /// `translation` is the total finger movement; a near-zero movement is treated as a tap.
    func endDrag(slot: Int, at location: CGPoint, translation: CGSize) {
        if drag == nil || hypot(translation.width, translation.height) < Self.tapSlop {
            if drag?.slot == slot { drag = nil }
            tapSlot(slot)
            return
        }
        guard drag?.slot == slot else { return }
        updateDrag(slot: slot, location: location)
        guard let current = drag else { return }
        if current.isValid, let origin = current.origin {
            drag = nil
            place(slot: slot, at: origin)
        } else {
            if current.origin != nil { app.feedback.play(.invalid) }
            returnDraggedPiece()
        }
    }

    func cancelDrag() {
        if drag != nil { returnDraggedPiece() }
    }

    /// Where the dragged piece is drawn: centred horizontally on the finger and lifted above it
    /// so the finger never hides the piece.
    func draggedPieceRect(for piece: PieceInstance, fingerAt location: CGPoint) -> CGRect {
        let width = CGFloat(piece.width) * cellSize
        let height = CGFloat(piece.height) * cellSize
        let lift = max(cellSize * 1.1, 40)
        return CGRect(x: location.x - width / 2, y: location.y - lift - height, width: width, height: height)
    }

    private func returnDraggedPiece() {
        guard var current = drag else { return }
        current.isReturning = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
            drag = current
        }
        let delay = reduceMotion ? 0 : 230
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self, self.drag?.slot == current.slot, self.drag?.isReturning == true else { return }
            self.drag = nil
        }
    }

    // MARK: Tap to place (accessible alternative to dragging)

    func tapSlot(_ slot: Int) {
        guard isInteractive, session.tray.piece(inSlot: slot) != nil else { return }
        isPulseArmed = false
        pulsePreviewCenter = nil
        selectedSlot = selectedSlot == slot ? nil : slot
        if selectedSlot != nil { showHint(.tapBoardToPlace) } else { clearHint() }
    }

    func tapCell(_ point: GridPoint) {
        guard isInteractive else { return }
        if isPulseArmed {
            handlePulseTap(at: point)
        } else if let slot = selectedSlot {
            if session.canPlace(slot: slot, at: point) {
                place(slot: slot, at: point)
            } else {
                app.feedback.play(.invalid)
                showHint(.doesNotFit)
            }
        }
    }

    // MARK: Pulse

    func togglePulse() {
        guard isInteractive, session.isPulseReady else { return }
        isPulseArmed.toggle()
        selectedSlot = nil
        pulsePreviewCenter = nil
        if isPulseArmed { showHint(.choosePulseArea) } else { clearHint() }
    }

    /// First tap previews the 3×3 area; tapping inside the preview confirms.
    private func handlePulseTap(at point: GridPoint) {
        if let center = pulsePreviewCenter, Set(session.pulseArea(centeredAt: center)).contains(point) {
            activatePulse(at: center)
        } else {
            pulsePreviewCenter = point
            showHint(.confirmPulse)
        }
    }

    private func activatePulse(at center: GridPoint) {
        let before = session.board
        do {
            let outcome = try session.activatePulse(at: center)
            isPulseArmed = false
            pulsePreviewCenter = nil
            clearHint()
            app.feedback.play(.pulse)
            persist()
            announce(String(localized: "Pulse cleared \(outcome.clearedCells.count) tiles."))
            animateResolution(from: before, clearing: outcome.clearedCells) { [weak self] in
                if outcome.isGameOver { self?.finishRound() }
            }
        } catch PulseError.nothingToClear {
            app.feedback.play(.invalid)
            showHint(.pulseAreaEmpty)
        } catch {
            app.feedback.play(.invalid)
        }
    }

    // MARK: Placement

    private func place(slot: Int, at origin: GridPoint) {
        guard isInteractive else { return }
        let outcome: PlacementOutcome
        do {
            outcome = try session.place(slot: slot, at: origin)
        } catch {
            app.feedback.play(.invalid)
            return
        }
        selectedSlot = nil
        clearHint()
        persist()

        // Feedback, most significant event wins the sound.
        if outcome.isCombo {
            app.feedback.play(.combo)
        } else if outcome.linesCleared > 0 {
            app.feedback.play(.clear(lines: outcome.linesCleared))
        } else {
            app.feedback.play(.place)
        }
        if outcome.pulseBecameReady {
            app.feedback.play(.pulseReady)
        } else if outcome.lumenCharged {
            app.feedback.play(.lumenCharged)
        }

        if outcome.linesCleared > 0 {
            showPopup(ScorePopup(points: outcome.score.total, lines: outcome.linesCleared,
                                 combo: outcome.isCombo ? outcome.comboStreak : nil, charged: outcome.lumenCharged))
            announce(String(localized: "Cleared \(outcome.linesCleared) lines. Score \(session.score)."))
        }
        if outcome.pulseBecameReady { showHint(.pulseReady) }

        animateResolution(from: outcome.boardBeforeClear, clearing: outcome.clearedCells) { [weak self] in
            guard let self else { return }
            if outcome.isGameOver {
                self.finishRound()
            } else if self.session.needsPulseToContinue {
                self.showHint(.usePulse)
            }
        }
    }

    private func animateResolution(from before: BoardState, clearing cleared: Set<GridPoint>, completion: @escaping () -> Void) {
        guard !cleared.isEmpty, !reduceMotion else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { displayBoard = session.board }
            clearingCells = []
            completion()
            return
        }
        isResolving = true
        displayBoard = before
        clearingCells = cleared
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self.displayBoard = self.session.board
                self.clearingCells = []
            }
            self.isResolving = false
            completion()
        }
    }

    // MARK: Round end

    private func finishRound() {
        guard result == nil, session.isGameOver else { return }
        let previousBest = app.progress.progress.previousBest(for: session.mode)
        let finished = session.makeResult(previousBestScore: previousBest, economy: AppConfiguration.economy)
        payout = app.progress.update { $0.record(finished, economy: AppConfiguration.economy) }
        app.ads.recordCompletedGame()
        app.feedback.play(.gameOver)
        drag = nil
        selectedSlot = nil
        isPulseArmed = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { result = finished }
        announce(String(localized: "Game over. Final score \(finished.score)."))
        Task { await app.ads.preload() }
    }

    func playAgain() {
        let mode = session.mode
        Task {
            await app.ads.showInterstitialIfDue()
            app.startNewGame(mode: mode)
        }
    }

    func leaveFinishedRound() {
        Task {
            await app.ads.showInterstitialIfDue()
            app.goHome()
        }
    }

    func watchRewardedAd() {
        guard rewardedState == .idle else { return }
        rewardedState = .showing
        Task {
            switch await app.ads.showRewarded() {
            case let .granted(coins): rewardedState = .granted(coins)
            case .notEarned: rewardedState = .notEarned
            case .unavailable, .alreadyInProgress: rewardedState = .unavailable
            }
        }
    }

    // MARK: Pause, restart, tutorial

    func pause() {
        guard result == nil else { return }
        cancelDrag()
        isPulseArmed = false
        isPaused = true
    }

    func resume() { isPaused = false }

    /// Abandons the current round (after confirmation in the UI). Not counted as a completed game.
    func restart() {
        isPaused = false
        app.startNewGame(mode: session.mode)
    }

    /// Leaves mid-round; the round stays saved and can be continued from Home.
    func leaveToHome() {
        persist()
        app.goHome()
    }

    func completeTutorial() {
        isTutorialVisible = false
        app.progress.update { $0.tutorialCompleted = true }
    }

    // MARK: Helpers

    private func persist() {
        let snapshot = session
        app.progress.update { $0.savedGame = snapshot.isGameOver ? nil : snapshot }
    }

    private func showPopup(_ value: ScorePopup) {
        popupTask?.cancel()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { popup = value }
        popupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.popup = nil }
        }
    }

    private func showHint(_ value: Hint) {
        hintTask?.cancel()
        hint = value
        guard value.isTransient else { return }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self, self.hint == value else { return }
            self.hint = nil
        }
    }

    private func clearHint() {
        hintTask?.cancel()
        hint = nil
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

// MARK: - Supporting types

struct DragState: Equatable {
    let slot: Int
    var location: CGPoint
    /// Snapped board origin for the piece, or nil when the piece is not over the board.
    var origin: GridPoint?
    var isValid: Bool
    var isReturning = false
}

struct ScorePopup: Equatable, Identifiable {
    let id = UUID()
    let points: Int
    let lines: Int
    let combo: Int?
    let charged: Bool
}

enum RewardedState: Equatable {
    case idle
    case showing
    case granted(Int)
    case notEarned
    case unavailable
}

enum Hint: Equatable {
    case tapBoardToPlace
    case doesNotFit
    case choosePulseArea
    case confirmPulse
    case pulseAreaEmpty
    case pulseReady
    case usePulse

    var isTransient: Bool {
        switch self {
        case .choosePulseArea, .confirmPulse, .usePulse, .tapBoardToPlace: return false
        default: return true
        }
    }

    var text: LocalizedStringKey {
        switch self {
        case .tapBoardToPlace: return "Tap a board cell to place the piece's top-left corner there."
        case .doesNotFit: return "That piece doesn't fit there."
        case .choosePulseArea: return "Pulse armed: tap the area you want to clear."
        case .confirmPulse: return "Tap inside the glowing area again to Pulse."
        case .pulseAreaEmpty: return "Nothing to clear there. Pick an area with tiles."
        case .pulseReady: return "Pulse is ready! Tap the Pulse button to clear a 3×3 area."
        case .usePulse: return "No piece fits. Use Pulse to clear space."
        }
    }
}
