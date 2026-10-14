import SwiftUI
import LumaGridEngine

/// The game screen: score header, board, Lumen/Pulse bar, and tray, plus pause, results, and
/// tutorial overlays. Layout adapts to the available height so the board stays the focus on
/// small and large iPhones alike.
struct GameView: View {
    static let coordinateSpaceName = "game"

    let game: GameViewModel
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let reduceMotion = systemReduceMotion || app.progress.settings.reduceMotion

        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let available = geometry.size
            let boardSide = min(available.width - horizontalPadding * 2, available.height * 0.56)
            let trayHeight = min(max(available.height * 0.16, 96), 150)

            ZStack {
                VStack(spacing: 12) {
                    GameHeader(game: game)
                    MessageRow(game: game)
                        .frame(height: 30)
                    BoardView(game: game)
                        .frame(width: boardSide, height: boardSide)
                    PulseBar(game: game)
                        .frame(width: boardSide)
                    Spacer(minLength: 4)
                    TrayView(game: game, slotHeight: trayHeight)
                        .frame(width: boardSide)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)

                DraggedPieceLayer(game: game)

                if game.isPaused {
                    PauseOverlay(game: game)
                        .transition(.opacity)
                }
                if game.result != nil {
                    GameOverView(game: game)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
                if game.isTutorialVisible {
                    TutorialView(onFinish: game.completeTutorial)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(.named(Self.coordinateSpaceName))
        }
        .environment(\.lumaReduceMotion, reduceMotion)
        .onAppear { game.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, newValue in game.reduceMotion = newValue }
        .onChange(of: scenePhase) { _, phase in
            // Interruptions (calls, app switch) pause the round; the state is already saved.
            if phase != .active, game.result == nil, !game.isTutorialVisible {
                game.pause()
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: game.isPaused)
    }
}

private struct GameHeader: View {
    let game: GameViewModel
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .center) {
            IconButton(systemImage: "pause.fill", label: "Pause") { game.pause() }
                .disabled(game.result != nil)

            Spacer()

            VStack(spacing: 2) {
                if case let .daily(dateKey) = game.mode {
                    Text("Daily · \(dateKey)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(LumaColors.secondaryText)
                }
                Text(game.session.score, format: .number)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LumaColors.text)
                    .contentTransition(.numericText(value: Double(game.session.score)))
                    .animation(.snappy, value: game.session.score)
                Text("Best \(game.bestScore)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(LumaColors.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Score \(game.session.score). Best \(game.bestScore)."))

            Spacer()

            CoinBadge(amount: app.progress.progress.coins)
        }
    }
}

/// Shows the latest score popup, or a contextual hint.
private struct MessageRow: View {
    let game: GameViewModel
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            if let popup = game.popup {
                HStack(spacing: 10) {
                    Text("+\(popup.points)")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(palette.accent)
                    Text(popup.lines == 1 ? "1 line" : "\(popup.lines) lines")
                        .foregroundStyle(LumaColors.text)
                    if let combo = popup.combo {
                        Text("Combo ×\(combo)")
                            .foregroundStyle(LumaColors.coin)
                    }
                    if popup.charged {
                        Label("Lumen", systemImage: "sparkle")
                            .foregroundStyle(palette.accent)
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(popup.id)
                .accessibilityHidden(true) // Announced by the view model instead.
            } else if let hint = game.hint {
                Text(hint.text)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(LumaColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The piece under the player's finger (or flying back to the tray after an invalid drop).
private struct DraggedPieceLayer: View {
    let game: GameViewModel

    var body: some View {
        ZStack {
            if let drag = game.drag, let piece = game.session.tray.piece(inSlot: drag.slot), game.cellSize > 0 {
                let rect = game.draggedPieceRect(for: piece, fingerAt: drag.location)
                let home = game.trayFrames[drag.slot]
                let returning = drag.isReturning && home != nil
                PieceShapeView(piece: piece, cellSize: returning ? game.trayCellSize : game.cellSize)
                    .position(x: returning ? home!.midX : rect.midX, y: returning ? home!.midY : rect.midY)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                    .opacity(returning ? 0.6 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
