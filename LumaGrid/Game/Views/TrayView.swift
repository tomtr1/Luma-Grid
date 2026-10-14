import SwiftUI
import LumaGridEngine

/// Draws a piece's tiles at a given cell size.
struct PieceShapeView: View {
    let piece: PieceInstance
    let cellSize: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(piece.cells.enumerated()), id: \.offset) { index, cell in
                TileView(color: palette.tile(piece.colorIndex), isPrism: index == piece.prismCellIndex, size: cellSize * 0.9)
                    .position(x: (CGFloat(cell.column) + 0.5) * cellSize, y: (CGFloat(cell.row) + 0.5) * cellSize)
            }
        }
        .frame(width: CGFloat(piece.width) * cellSize, height: CGFloat(piece.height) * cellSize)
    }
}

/// The three-piece tray. Pieces can be dragged onto the board, or tapped to select and then
/// placed by tapping a board cell (the accessible alternative).
struct TrayView: View {
    let game: GameViewModel
    let slotHeight: CGFloat
    @Environment(\.palette) private var palette

    var body: some View {
        let traySize = game.session.configuration.traySize
        GeometryReader { geometry in
            let slotWidth = (geometry.size.width - CGFloat(traySize - 1) * 10) / CGFloat(traySize)
            let cell = min(slotWidth / 5.6, slotHeight / 5.6, max(game.cellSize * 0.6, 12))
            HStack(spacing: 10) {
                ForEach(0..<traySize, id: \.self) { slot in
                    slotView(slot: slot, cell: cell)
                        .frame(width: slotWidth, height: slotHeight)
                }
            }
            .onAppear { game.trayCellSize = cell }
            .onChange(of: cell) { _, newValue in game.trayCellSize = newValue }
        }
        .frame(height: slotHeight)
    }

    @ViewBuilder
    private func slotView(slot: Int, cell: CGFloat) -> some View {
        let piece = game.session.tray.piece(inSlot: slot)
        let isDragging = game.drag?.slot == slot
        let isSelected = game.selectedSlot == slot
        let fits = piece.map { game.session.board.hasLegalPlacement(for: $0) } ?? false

        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? palette.accent.opacity(0.14) : LumaColors.panel.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? palette.accent : LumaColors.panelStroke, lineWidth: isSelected ? 2 : 1)
                )

            if let piece, !isDragging {
                PieceShapeView(piece: piece, cellSize: cell)
                    .opacity(fits ? 1 : 0.35)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .id(piece.id)
            }
        }
        .onFrameChange(in: .named(GameView.coordinateSpaceName)) { frame in
            game.trayFrames[slot] = frame
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(GameView.coordinateSpaceName))
                .onChanged { value in game.beginDrag(slot: slot, at: value.location) }
                .onEnded { value in game.endDrag(slot: slot, at: value.location, translation: value.translation) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label(for: piece, fits: fits)))
        .accessibilityHint(piece == nil ? Text("") : Text("Double-tap to select, then choose a board cell for the piece's top-left corner."))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { game.tapSlot(slot) }
    }

    private func label(for piece: PieceInstance?, fits: Bool) -> String {
        guard let piece else { return String(localized: "Empty slot") }
        var parts = [String(localized: "\(piece.cells.count)-tile piece, \(piece.width) wide by \(piece.height) tall")]
        if piece.hasPrism { parts.append(String(localized: "contains a prism tile")) }
        if !fits { parts.append(String(localized: "does not fit anywhere right now")) }
        return parts.joined(separator: ", ")
    }
}

extension View {
    /// Reports this view's frame in the given coordinate space whenever it changes.
    func onFrameChange(in space: CoordinateSpace, perform action: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { action(proxy.frame(in: space)) }
                    .onChange(of: proxy.frame(in: space)) { _, newValue in action(newValue) }
            }
        )
    }
}
