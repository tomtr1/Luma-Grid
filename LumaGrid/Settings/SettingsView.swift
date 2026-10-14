import SwiftUI
import LumaGridServices

/// Settings: sound, haptics, motion, tutorial, purchases, privacy choices, links, version.
/// Links appear only when real URLs are configured, so there are no dead buttons.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var showTutorial = false
    @State private var showCredits = false

    var body: some View {
        NavigationStack {
            List {
                Section("Gameplay") {
                    Toggle("Sound", isOn: setting(\.soundEnabled))
                    Toggle("Haptics", isOn: setting(\.hapticsEnabled))
                    Toggle(isOn: setting(\.reduceMotion)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reduce Animations")
                            if systemReduceMotion {
                                Text("Your device's Reduce Motion setting is on, so animations are already reduced.")
                                    .font(.footnote)
                                    .foregroundStyle(LumaColors.secondaryText)
                            }
                        }
                    }
                    Button("How to Play") { showTutorial = true }
                }

                Section("Purchases") {
                    Button {
                        Task { await app.store.restorePurchases() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            Spacer()
                            if app.store.isRestoring { ProgressView() }
                        }
                    }
                    .disabled(app.store.isRestoring)
                    if app.progress.hasRemoveForcedAds {
                        Label("Remove Forced Ads is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(LumaColors.coin)
                    }
                }

                Section("Privacy") {
                    if app.ads.isPrivacyOptionsRequired {
                        Button("Ad Privacy Choices") {
                            Task { await app.ads.presentPrivacyOptions() }
                        }
                    }
                    if let url = AppConfiguration.privacyPolicyURL {
                        Link("Privacy Policy", destination: url)
                    }
                    Text("LumaGrid has no accounts and keeps your progress on this device. Ads are provided by Google AdMob; see the privacy policy for details.")
                        .font(.footnote)
                        .foregroundStyle(LumaColors.secondaryText)
                }

                Section("About") {
                    if let url = AppConfiguration.supportURL {
                        Link("Support", destination: url)
                    }
                    Button("Credits") { showCredits = true }
                    LabeledContent("Version", value: AppConfiguration.versionDescription)
                    #if DEBUG
                    LabeledContent("Ads", value: adsStatusText)
                    #endif
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(Color(hex: "#5FE3C0"))
        }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView { showTutorial = false }
                .themed(ThemePalette(app.progress.selectedTheme))
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showCredits) {
            CreditsView()
                .themed(ThemePalette(app.progress.selectedTheme))
                .preferredColorScheme(.dark)
        }
    }

    private func setting(_ keyPath: WritableKeyPath<GameSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.progress.settings[keyPath: keyPath] },
            set: { value in app.progress.update { $0.settings[keyPath: keyPath] = value } }
        )
    }

    #if DEBUG
    private var adsStatusText: String {
        switch app.ads.status {
        case let .enabled(usingTestAds): return usingTestAds ? "Test ads" : "Live ads"
        case let .disabled(reason): return "Off – \(reason)"
        }
    }
    #endif
}

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(AppConfiguration.displayName) is an original puzzle game.")
                    Text("Design, code, artwork, and sound effects were created for this project. Sound effects are synthesized tones generated by the project's own scripts.")
                    Text("Advertising is provided by the Google Mobile Ads SDK and consent by Google's User Messaging Platform SDK, used under their respective terms.")
                    Text("LumaGrid is not affiliated with Apple, Google, or any other game or brand.")
                }
                .font(.system(.body, design: .rounded))
                .foregroundStyle(LumaColors.text)
                .padding(20)
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
