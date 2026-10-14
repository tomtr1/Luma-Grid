import SwiftUI
import LumaGridEngine

/// Results screen. Coins for the round are already credited; the rewarded ad is a purely optional
/// extra. Interstitials (if due) appear only after the player taps Play Again or Home.
struct GameOverView: View {
    let game: GameViewModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var confirmRewarded = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            if let result = game.result {
                Panel {
                    VStack(spacing: 16) {
                        Text(result.isNewBest ? "New Best!" : "Round Complete")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(result.isNewBest ? LumaColors.coin : LumaColors.text)
                            .accessibilityAddTraits(.isHeader)

                        Text(result.score, format: .number)
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(LumaColors.text)
                            .accessibilityLabel(Text("Final score \(result.score)"))

                        Text("Best \(result.bestScore)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LumaColors.secondaryText)

                        Grid(horizontalSpacing: 18, verticalSpacing: 8) {
                            statRow("Lines cleared", value: result.linesCleared)
                            statRow("Best combo", value: result.bestComboStreak)
                            if result.pulsesUsed > 0 { statRow("Pulses used", value: result.pulsesUsed) }
                            statRow("Coins earned", value: game.payout?.total ?? result.coinsEarned)
                        }
                        .font(.system(.subheadline, design: .rounded))

                        if let payout = game.payout, payout.dailyBonusCoins > 0 {
                            Text("Includes a daily puzzle bonus of \(payout.dailyBonusCoins) coins.")
                                .font(.footnote)
                                .foregroundStyle(LumaColors.coin)
                        }

                        rewardedSection

                        Button("Play Again") { game.playAgain() }
                            .buttonStyle(LumaButtonStyle(kind: .primary))
                        Button("Home") { game.leaveFinishedRound() }
                            .buttonStyle(LumaButtonStyle(kind: .secondary))
                    }
                }
                .frame(maxWidth: 380)
                .padding(24)
            }
        }
        .task { await app.ads.preload() }
        .confirmationDialog("Watch an ad to earn \(app.ads.rewardedCoins) coins?", isPresented: $confirmRewarded, titleVisibility: .visible) {
            Button("Watch Ad") { game.watchRewardedAd() }
            Button("No Thanks", role: .cancel) {}
        } message: {
            Text("The coins are added after the ad finishes. Closing it early earns nothing, and your round rewards are already yours.")
        }
    }

    @ViewBuilder
    private var rewardedSection: some View {
        switch game.rewardedState {
        case .idle:
            if app.ads.isRewardedReady {
                Button {
                    confirmRewarded = true
                } label: {
                    Label("Watch an ad for +\(app.ads.rewardedCoins) coins", systemImage: "play.rectangle")
                }
                .buttonStyle(LumaButtonStyle(kind: .secondary))
                .padding(.top, 4)
            }
        case .showing:
            ProgressView().tint(LumaColors.text)
        case let .granted(coins):
            Label("+\(coins) coins added", systemImage: "checkmark.circle.fill")
                .foregroundStyle(LumaColors.coin)
        case .notEarned:
            Text("The ad was closed before the reward was earned.")
                .font(.footnote)
                .foregroundStyle(LumaColors.secondaryText)
        case .unavailable:
            Text("No ad is available right now. Your balance is unchanged.")
                .font(.footnote)
                .foregroundStyle(LumaColors.secondaryText)
        }
    }

    private func statRow(_ title: LocalizedStringKey, value: Int) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(LumaColors.secondaryText)
                .gridColumnAlignment(.leading)
            Text(value, format: .number)
                .monospacedDigit()
                .foregroundStyle(LumaColors.text)
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
