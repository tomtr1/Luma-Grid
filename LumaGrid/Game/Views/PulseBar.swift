import SwiftUI

/// Lumen meter (charge pips) and the Pulse button.
struct PulseBar: View {
    let game: GameViewModel
    @Environment(\.palette) private var palette
    @Environment(\.lumaReduceMotion) private var reduceMotion

    var body: some View {
        let charge = game.session.lumenCharge
        let required = game.session.configuration.lumen.chargesForPulse
        let ready = game.session.isPulseReady

        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.accent)
                Text("Lumen")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(LumaColors.secondaryText)
                HStack(spacing: 5) {
                    ForEach(0..<required, id: \.self) { index in
                        Diamond()
                            .fill(index < charge ? palette.accent : Color.white.opacity(0.12))
                            .overlay(Diamond().stroke(palette.accent.opacity(0.6), lineWidth: 1))
                            .frame(width: 14, height: 18)
                            .shadow(color: index < charge ? palette.accent.opacity(0.7) : .clear, radius: 5)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Lumen meter, \(charge) of \(required)"))
            .accessibilityHint(Text("Clear lines containing star prism tiles to charge Pulse."))

            Spacer(minLength: 8)

            Button(action: game.togglePulse) {
                HStack(spacing: 6) {
                    Image(systemName: game.isPulseArmed ? "xmark" : "dot.radiowaves.left.and.right")
                    Text(game.isPulseArmed ? "Cancel" : "Pulse")
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(ready ? Color(hex: "#0B0A1F") : LumaColors.secondaryText)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(
                    Capsule().fill(ready ? AnyShapeStyle(palette.accent) : AnyShapeStyle(LumaColors.panel))
                )
                .overlay(Capsule().strokeBorder(ready ? Color.white.opacity(0.4) : LumaColors.panelStroke, lineWidth: 1))
                .shadow(color: ready ? palette.accent.opacity(game.session.needsPulseToContinue ? 0.9 : 0.5) : .clear, radius: 10)
                .scaleEffect(ready && game.session.needsPulseToContinue && !reduceMotion ? 1.06 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: game.session.needsPulseToContinue)
            }
            .disabled(!ready || !game.isInteractive)
            .accessibilityLabel(Text(game.isPulseArmed ? "Cancel Pulse" : (ready ? "Pulse, ready" : "Pulse, not charged")))
            .accessibilityHint(Text("Clears every tile in a 3 by 3 area you choose."))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(LumaColors.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
