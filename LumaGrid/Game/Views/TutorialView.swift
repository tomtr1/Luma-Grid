import SwiftUI

/// Short, skippable first-play tutorial (three cards). Also reachable from Settings > How to Play.
struct TutorialView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @Environment(\.palette) private var palette

    private struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(symbol: "hand.draw",
             title: "Place pieces",
             body: "Drag a piece from the tray onto the board. A glowing outline shows where it will land. You can also tap a piece, then tap a cell."),
        Page(symbol: "square.grid.3x3.fill",
             title: "Clear lines",
             body: "Fill a whole row or column to clear it. Clear lines on back-to-back moves for combo bonuses. The round ends when no piece fits."),
        Page(symbol: "sparkle",
             title: "Charge your Pulse",
             body: "Tiles marked with a star are Prisms. Clear a line containing one to charge the Lumen meter. At 3 charges, Pulse clears any 3×3 area."),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            Panel {
                VStack(spacing: 18) {
                    let current = pages[page]
                    Image(systemName: current.symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(height: 56)
                        .accessibilityHidden(true)
                    Text(current.title)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(LumaColors.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(current.body)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(LumaColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? palette.accent : Color.white.opacity(0.2))
                                .frame(width: index == page ? 22 : 8, height: 8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Step \(page + 1) of \(pages.count)"))

                    Button(page == pages.count - 1 ? "Start Playing" : "Next") {
                        if page == pages.count - 1 {
                            onFinish()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(LumaButtonStyle(kind: .primary))

                    if page < pages.count - 1 {
                        Button("Skip") { onFinish() }
                            .buttonStyle(LumaButtonStyle(kind: .subtle))
                    }
                }
            }
            .frame(maxWidth: 380)
            .padding(24)
        }
    }
}
