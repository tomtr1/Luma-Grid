import SwiftUI

/// Pause menu. Never shows ads.
struct PauseOverlay: View {
    let game: GameViewModel
    @Environment(AppModel.self) private var app
    @State private var confirmRestart = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { game.resume() }
                .accessibilityHidden(true)

            Panel {
                VStack(spacing: 14) {
                    Text("Paused")
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(LumaColors.text)
                        .accessibilityAddTraits(.isHeader)

                    Button("Resume") { game.resume() }
                        .buttonStyle(LumaButtonStyle(kind: .primary))

                    Toggle(isOn: soundBinding) { Label("Sound", systemImage: "speaker.wave.2.fill") }
                    Toggle(isOn: hapticsBinding) { Label("Haptics", systemImage: "iphone.radiowaves.left.and.right") }

                    Button("Restart") { confirmRestart = true }
                        .buttonStyle(LumaButtonStyle(kind: .secondary))
                    Button("Home") { game.leaveToHome() }
                        .buttonStyle(LumaButtonStyle(kind: .secondary))
                    Text("Your game is saved. Continue it from Home.")
                        .font(.footnote)
                        .foregroundStyle(LumaColors.secondaryText)
                }
                .toggleStyle(.switch)
                .tint(Color(hex: "#5FE3C0"))
                .foregroundStyle(LumaColors.text)
            }
            .frame(maxWidth: 360)
            .padding(24)
        }
        .confirmationDialog("Restart this round?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { game.restart() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Your current score will be lost.")
        }
    }

    private var soundBinding: Binding<Bool> {
        Binding(get: { app.progress.settings.soundEnabled },
                set: { value in app.progress.update { $0.settings.soundEnabled = value } })
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(get: { app.progress.settings.hapticsEnabled },
                set: { value in app.progress.update { $0.settings.hapticsEnabled = value } })
    }
}
