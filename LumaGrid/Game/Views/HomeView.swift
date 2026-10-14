import SwiftUI
import LumaGridEngine

/// Home screen: logo, Play/Continue, Daily Puzzle, best score, coins, Shop, Settings.
/// No ads are shown here or at launch.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirmNewGame = false

    var body: some View {
        let progress = app.progress.progress
        let todayKey = AppModel.todayKey()
        let dailyBest = progress.daily.bestScores[todayKey]
        let dailyBonusPending = !progress.daily.bonusPaidDateKeys.contains(todayKey)

        VStack(spacing: 0) {
            HStack {
                CoinBadge(amount: progress.coins)
                Spacer()
                IconButton(systemImage: "bag.fill", label: "Shop") { app.isShopPresented = true }
                IconButton(systemImage: "gearshape.fill", label: "Settings") { app.isSettingsPresented = true }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
            LogoLockup()
            Spacer()

            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("Best Score")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(LumaColors.secondaryText)
                        .textCase(.uppercase)
                    Text(progress.bestScore, format: .number)
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(LumaColors.text)
                }
                .accessibilityElement(children: .combine)
                .padding(.bottom, 8)

                if let saved = app.savedGame {
                    Button {
                        app.resumeSavedGame()
                    } label: {
                        Label {
                            if saved.mode.isDaily {
                                Text("Continue Daily · \(saved.score)")
                            } else {
                                Text("Continue · \(saved.score)")
                            }
                        } icon: {
                            Image(systemName: "play.fill")
                        }
                    }
                    .buttonStyle(LumaButtonStyle(kind: .primary))
                    .accessibilityIdentifier("continueButton")

                    Button("New Game") { confirmNewGame = true }
                        .buttonStyle(LumaButtonStyle(kind: .secondary))
                } else {
                    Button {
                        app.startNewGame()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(LumaButtonStyle(kind: .primary))
                    .accessibilityIdentifier("playButton")
                }

                Button {
                    app.startNewGame(mode: .daily(dateKey: todayKey))
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Daily Puzzle")
                        Spacer()
                        if let dailyBest {
                            Text("Best \(dailyBest)")
                                .foregroundStyle(LumaColors.secondaryText)
                        } else if dailyBonusPending {
                            Text("+\(AppConfiguration.economy.dailyCompletionBonus) bonus")
                                .foregroundStyle(LumaColors.coin)
                        }
                    }
                }
                .buttonStyle(LumaButtonStyle(kind: .secondary))
                .accessibilityHint(Text("The same pieces for everyone today. Finish it once for a coin bonus."))
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .confirmationDialog("Start a new game?", isPresented: $confirmNewGame, titleVisibility: .visible) {
            Button("New Game", role: .destructive) { app.startNewGame() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved game will be replaced.")
        }
    }
}
