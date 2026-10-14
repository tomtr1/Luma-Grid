import SwiftUI

/// Switches between Home and the game, applies the selected theme, and hosts the Shop and
/// Settings sheets.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let palette = ThemePalette(app.progress.selectedTheme)

        ZStack {
            switch app.screen {
            case .home:
                HomeView()
                    .transition(.opacity)
            case .game:
                if let game = app.game {
                    GameView(game: game)
                        .id(ObjectIdentifier(game))
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.screen)
        .themed(palette)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $app.isShopPresented) {
            ShopView()
                .themed(palette)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $app.isSettingsPresented) {
            SettingsView()
                .themed(palette)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview())
}
