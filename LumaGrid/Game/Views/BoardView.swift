import SwiftUI
import LumaGridEngine

/// The 9×9 board. Renders `displayBoard` (the engine's decided state, possibly mid-animation),
/// the drag ghost, and the Pulse preview. Taps are forwarded to the view model.
struct BoardView: View {
    let game: GameViewModel
    @Environment(\.palette) private var palette
    @Environment(\.lumaReduceMotion) private var reduceMotion

    var body: some View {
        let board = game.displayBoard
        let ghost = Set(game.ghostCells)
        let ghostValid = game.drag?.isValid ?? false
        let ghostColor = game.drag.flatMap { game.session.tray.piece(inSlot: $0.slot) }.map { palette.tile($0.colorIndex) } ?? palette.accent
        let ghostPrismCell: GridPoint? = {
            guard let drag = game.drag, let origin = drag.origin, let piece = game.session.tray.piece(inSlot: drag.slot),
                  let index = piece.prismCellIndex else { return nil }
            return origin + piece.cells[index]
        }()
        let pulseArea = game.pulsePreviewArea

        GeometryReader { geometry in
            let cell = geometry.size.width / CGFloat(board.size)
            let tileSize = cell * 0.9

            ZStack(alignment: .topLeading) {
                // Empty cells
                Canvas { context, size in
                    for point in board.allPoints {
                        let rect = CGRect(x: CGFloat(point.column) * cell, y: CGFloat(point.row) * cell, width: cell, height: cell)
                            .insetBy(dx: cell * 0.05, dy: cell * 0.05)
                        let path = Path(roundedRect: rect, cornerRadius: cell * 0.2, style: .continuous)
                        context.fill(path, with: .color(palette.boardCell))
                    }
                }

                // Pulse target preview
                if !pulseArea.isEmpty {
                    ForEach(Array(pulseArea), id: \.self) { point in
                        RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                            .fill(palette.accent.opacity(0.28))
                            .overlay(RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous).strokeBorder(palette.accent, lineWidth: 1.5))
                            .frame(width: cell * 0.96, height: cell * 0.96)
                            .position(center(of: point, cell: cell))
                    }
                }

                // Tiles
                ForEach(board.allPoints.filter { board[$0] != nil }, id: \.self) { point in
                    if let tile = board[point] {
                        TileView(color: palette.tile(tile.colorIndex), isPrism: tile.isPrism,
                                 style: game.clearingCells.contains(point) ? .clearing : .solid, size: tileSize)
                            .position(center(of: point, cell: cell))
                            .transition(reduceMotion ? .identity : .scale(scale: 0.4).combined(with: .opacity))
                    }
                }

                // Drag ghost
                ForEach(Array(ghost), id: \.self) { point in
                    TileView(color: ghostColor, isPrism: point == ghostPrismCell, style: .ghost(valid: ghostValid), size: tileSize)
                        .position(center(of: point, cell: cell))
                        .allowsHitTesting(false)
                }

                accessibilityLayer(board: board, cell: cell)
            }
            .contentShape(Rectangle())
            .onFrameChange(in: .named(GameView.coordinateSpaceName)) { frame in
                game.boardFrame = frame
            }
            .onTapGesture(coordinateSpace: .local) { location in
                let point = GridPoint(row: Int(location.y / cell), column: Int(location.x / cell))
                if board.contains(point) { game.tapCell(point) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(6)
        .background(palette.boardBacking, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: palette.accent.opacity(0.12), radius: 24)
    }

    private func center(of point: GridPoint, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(point.column) + 0.5) * cell, y: (CGFloat(point.row) + 0.5) * cell)
    }

    /// One VoiceOver element per cell. Cells become actionable when a piece is selected or Pulse is armed.
    private func accessibilityLayer(board: BoardState, cell: CGFloat) -> some View {
        ForEach(board.allPoints, id: \.self) { point in
            Color.clear
                .frame(width: cell, height: cell)
                .position(center(of: point, cell: cell))
                .accessibilityElement()
                .accessibilityLabel(Text(cellLabel(point, board: board)))
                .accessibilityAddTraits(game.selectedSlot != nil || game.isPulseArmed ? .isButton : [])
                .accessibilityAction { game.tapCell(point) }
                .allowsHitTesting(false)
        }
    }

    private func cellLabel(_ point: GridPoint, board: BoardState) -> String {
        let position = String(localized: "Row \(point.row + 1), column \(point.column + 1)")
        guard let tile = board[point] else { return String(localized: "\(position), empty") }
        return tile.isPrism ? String(localized: "\(position), prism tile") : String(localized: "\(position), filled")
    }
}
