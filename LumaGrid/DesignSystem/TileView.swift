import SwiftUI
import UIKit

/// A single luminous tile. Prism tiles carry a star symbol so their status never relies on color alone.
struct TileView: View {
    enum Style {
        case solid
        /// Drop preview: translucent, outlined.
        case ghost(valid: Bool)
        /// About to be cleared: brightened.
        case clearing
    }

    let color: Color
    var isPrism = false
    var style: Style = .solid
    var size: CGFloat

    private var cornerRadius: CGFloat { size * 0.22 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            switch style {
            case .solid, .clearing:
                shape
                    .fill(
                        LinearGradient(
                            colors: [color.blended(with: .white, amount: isClearing ? 0.55 : 0.18), color, color.blended(with: .black, amount: 0.18)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .top) {
                        // Top highlight for subtle depth.
                        RoundedRectangle(cornerRadius: cornerRadius * 0.7, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .frame(height: size * 0.38)
                            .padding(.horizontal, size * 0.1)
                            .padding(.top, size * 0.07)
                    }
                    .shadow(color: color.opacity(isClearing ? 0.9 : 0.35), radius: isClearing ? size * 0.4 : size * 0.12)
            case let .ghost(valid):
                shape
                    .fill(valid ? color.opacity(0.35) : LumaColors.invalid.opacity(0.18))
                    .overlay(
                        shape.strokeBorder(valid ? color.opacity(0.9) : LumaColors.invalid.opacity(0.8),
                                           style: StrokeStyle(lineWidth: max(1, size * 0.06), dash: valid ? [] : [size * 0.12, size * 0.08]))
                    )
            }

            if isPrism {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isGhost ? 0.7 : 0.95))
                    .shadow(color: .white.opacity(0.8), radius: size * 0.12)
            }
        }
        .frame(width: size, height: size)
    }

    private var isClearing: Bool {
        if case .clearing = style { return true }
        return false
    }

    private var isGhost: Bool {
        if case .ghost = style { return true }
        return false
    }
}

extension Color {
    /// Blends toward `other` (0…1). Implemented manually to support iOS 17.
    func blended(with other: Color, amount: Double) -> Color {
        let a = UIColor(self)
        let b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1), b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let t = CGFloat(min(max(amount, 0), 1))
        return Color(.sRGB, red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t), opacity: Double(a1 + (a2 - a1) * t))
    }
}
