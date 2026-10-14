import SwiftUI

/// Large rounded button used for primary actions (Play, Play Again).
struct LumaButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, subtle }
    var kind: Kind = .primary
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: kind == .subtle, vertical: false)
            .foregroundStyle(foreground)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .frame(maxWidth: kind == .subtle ? nil : .infinity, minHeight: 50)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(kind == .primary ? Color.clear : LumaColors.panelStroke, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        kind == .primary ? Color(hex: "#0B0A1F") : LumaColors.text
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary:
            return AnyShapeStyle(LinearGradient(colors: [palette.accent, palette.tile(0)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .secondary:
            return AnyShapeStyle(LumaColors.panel)
        case .subtle:
            return AnyShapeStyle(Color.clear)
        }
    }
}

/// Round icon button for the game header (pause, etc.). Minimum 44×44 touch target.
struct IconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LumaColors.text)
                .frame(width: 44, height: 44)
                .background(LumaColors.panel, in: Circle())
                .overlay(Circle().strokeBorder(LumaColors.panelStroke, lineWidth: 1))
        }
        .accessibilityLabel(Text(label))
    }
}

struct CoinBadge: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(LumaColors.coin)
                .accessibilityHidden(true)
            Text(amount, format: .number)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(LumaColors.text)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LumaColors.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(LumaColors.panelStroke, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(amount) coins"))
    }
}

/// Translucent card used by overlays and the shop.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(Color(hex: "#141233").opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(LumaColors.panelStroke, lineWidth: 1))
    }
}

/// The wordmark: original lockup of a small glowing 2×2 tile mark plus the display name.
struct LogoLockup: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    TileView(color: palette.tile(0), size: 34)
                    TileView(color: palette.tile(1), size: 34)
                }
                GridRow {
                    TileView(color: palette.tile(2), size: 34)
                    TileView(color: palette.tile(4), isPrism: true, size: 34)
                }
            }
            .shadow(color: palette.accent.opacity(0.35), radius: 18)

            Text(AppConfiguration.displayName)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(LumaColors.text)
                .tracking(1)
            Text("Place. Clear. Glow.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(LumaColors.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppConfiguration.displayName))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Applies the active theme's background and environment values to a screen.
struct ThemedBackground: ViewModifier {
    let palette: ThemePalette

    func body(content: Content) -> some View {
        content
            .background(palette.background.ignoresSafeArea())
            .environment(\.palette, palette)
    }
}

extension View {
    func themed(_ palette: ThemePalette) -> some View {
        modifier(ThemedBackground(palette: palette))
    }
}
