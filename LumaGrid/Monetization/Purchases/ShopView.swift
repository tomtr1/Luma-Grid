import StoreKit
import SwiftUI
import LumaGridServices

/// Simple, honest shop: themes (coins or purchase), Remove Forced Ads, and coin packs.
/// Names and prices come from StoreKit; nothing is shown as purchased until StoreKit verifies it.
struct ShopView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var themeToUnlock: ThemeDefinition?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text("Your coins")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(LumaColors.secondaryText)
                        Spacer()
                        CoinBadge(amount: app.progress.progress.coins)
                    }
                    storeStatus
                    themesSection
                    removeAdsSection
                    coinsSection
                    restoreSection
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            if app.store.loadState != .loaded || !app.store.hasAnyProducts {
                await app.store.loadProducts()
            }
        }
        .alert(
            app.store.feedback.map(alertTitle) ?? Text(""),
            isPresented: Binding(get: { app.store.feedback != nil }, set: { if !$0 { app.store.feedback = nil } }),
            presenting: app.store.feedback
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { feedback in
            alertMessage(feedback)
        }
        .confirmationDialog(
            unlockTitle(for: themeToUnlock),
            isPresented: Binding(get: { themeToUnlock != nil }, set: { if !$0 { themeToUnlock = nil } }),
            titleVisibility: .visible,
            presenting: themeToUnlock
        ) { theme in
            Button("Unlock") { unlockWithCoins(theme) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var storeStatus: some View {
        switch app.store.loadState {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView().tint(LumaColors.text)
                Text("Loading the store…").foregroundStyle(LumaColors.secondaryText)
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text("The store couldn't be reached.").foregroundStyle(LumaColors.text)
                Text(message).font(.footnote).foregroundStyle(LumaColors.secondaryText)
                Button("Try Again") { Task { await app.store.loadProducts() } }
                    .buttonStyle(LumaButtonStyle(kind: .secondary))
            }
        case .loaded where !app.store.hasAnyProducts:
            VStack(alignment: .leading, spacing: 6) {
                Text("Purchases aren't available right now. Coin themes can still be unlocked.")
                    .foregroundStyle(LumaColors.secondaryText)
                #if DEBUG
                Text("Developer note: no products were returned for \(app.store.catalog.allIDs.joined(separator: ", ")). Run the LumaGrid scheme with LumaGrid.storekit selected, or create these products in App Store Connect.")
                    .font(.footnote)
                    .foregroundStyle(LumaColors.coin)
                #endif
            }
        case .loaded:
            EmptyView()
        }
    }

    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Themes", subtitle: "Cosmetic only. Every theme plays exactly the same.")
            ForEach(AppConfiguration.themes) { theme in
                themeRow(theme)
            }
        }
    }

    private func themeRow(_ theme: ThemeDefinition) -> some View {
        let palette = ThemePalette(theme)
        return HStack(spacing: 14) {
            ThemeSwatch(palette: palette)
            Text(ThemeText.name(for: theme.id))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(LumaColors.text)
            Spacer()
            themeAction(theme, accent: palette.accent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumaColors.panel))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func themeAction(_ theme: ThemeDefinition, accent: Color) -> some View {
        let progress: PlayerProgress = app.progress.progress
        if progress.selectedThemeID == theme.id {
            Label("Selected", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
        } else if progress.isThemeUnlocked(theme) {
            Button("Use") { selectTheme(theme) }
                .buttonStyle(LumaButtonStyle(kind: .subtle))
        } else if case let .coins(price) = theme.unlock {
            Button {
                themeToUnlock = theme
            } label: {
                Label("\(price)", systemImage: "circle.hexagongrid.fill")
            }
            .buttonStyle(LumaButtonStyle(kind: .subtle))
            .disabled(progress.coins < price)
            .accessibilityLabel(Text("Unlock for \(price) coins"))
        } else if case let .purchase(productID) = theme.unlock {
            purchaseButton(productID: productID)
        }
    }

    private func selectTheme(_ theme: ThemeDefinition) {
        _ = app.progress.update { progress -> Bool in progress.selectTheme(theme) }
    }

    private var removeAdsSection: some View {
        let id = app.store.catalog.identifiers.removeForcedAds
        let owned = app.progress.hasRemoveForcedAds
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Remove Forced Ads",
                          subtitle: "Removes the ads shown automatically between games, permanently. Optional ads you choose to watch for coins stay available. Restorable on your other devices.")
            HStack {
                Text(app.store.product(for: id)?.displayName ?? String(localized: "Remove Forced Ads"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(LumaColors.text)
                Spacer()
                if owned {
                    Label("Purchased", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(LumaColors.coin)
                } else {
                    purchaseButton(productID: id)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumaColors.panel))
        }
    }

    private var coinsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Coins", subtitle: "Coins unlock cosmetic themes. They are stored on this device and are not restored on a new device.")
            ForEach(app.store.catalog.products.filter(\.kind.isConsumable)) { definition in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.store.product(for: definition.id)?.displayName ?? coinsFallbackName(definition))
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(LumaColors.text)
                        if let description = app.store.product(for: definition.id)?.description, !description.isEmpty {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(LumaColors.secondaryText)
                        }
                    }
                    Spacer()
                    purchaseButton(productID: definition.id)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumaColors.panel))
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await app.store.restorePurchases() }
            } label: {
                if app.store.isRestoring {
                    ProgressView().tint(LumaColors.text)
                } else {
                    Text("Restore Purchases")
                }
            }
            .buttonStyle(LumaButtonStyle(kind: .secondary))
            .disabled(app.store.isRestoring)
            Text("Restores Remove Forced Ads and theme packs bought with your Apple Account.")
                .font(.footnote)
                .foregroundStyle(LumaColors.secondaryText)
        }
    }

    // MARK: Components

    @ViewBuilder
    private func purchaseButton(productID: String) -> some View {
        if let product = app.store.product(for: productID) {
            Button {
                buy(product)
            } label: {
                if app.store.inFlightProductID == productID {
                    ProgressView().tint(LumaColors.text)
                } else {
                    Text(product.displayPrice)
                }
            }
            .buttonStyle(LumaButtonStyle(kind: .subtle))
            .disabled(app.store.inFlightProductID != nil)
            .accessibilityLabel(Text("Buy \(product.displayName) for \(product.displayPrice)"))
        } else {
            Text("Unavailable")
                .font(.footnote)
                .foregroundStyle(LumaColors.secondaryText)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(LumaColors.text)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(LumaColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func unlockTitle(for theme: ThemeDefinition?) -> String {
        guard let theme, case let .coins(price) = theme.unlock else { return "" }
        return String(localized: "Unlock \(ThemeText.name(for: theme.id)) for \(price) coins?")
    }

    private func coinsFallbackName(_ definition: ProductDefinition) -> String {
        if case let .consumableCoins(amount) = definition.kind {
            return String(localized: "\(amount) Coins")
        }
        return definition.id
    }

    // MARK: Actions

    private func buy(_ product: Product) {
        guard app.store.beginPurchase(of: product.id) else { return }
        Task {
            do {
                let result = try await purchase(product)
                await app.store.completePurchase(of: product, result: .success(result))
            } catch {
                await app.store.completePurchase(of: product, result: .failure(error))
            }
        }
    }

    private func unlockWithCoins(_ theme: ThemeDefinition) {
        let result = app.progress.update { progress -> ThemeUnlockResult in
            let outcome = progress.unlockThemeWithCoins(theme)
            if outcome == .unlocked { progress.selectTheme(theme) }
            return outcome
        }
        if result == .unlocked { app.feedback.play(.combo) }
        themeToUnlock = nil
    }

    private func alertTitle(_ feedback: StoreService.Feedback) -> Text {
        switch feedback {
        case .purchased: return Text("Thank you!")
        case .pending: return Text("Purchase Pending")
        case .cancelled: return Text("Purchase Cancelled")
        case .failed: return Text("Purchase Failed")
        case .restored: return Text("Purchases Restored")
        case .restoreFailed: return Text("Restore Failed")
        }
    }

    private func alertMessage(_ feedback: StoreService.Feedback) -> Text {
        switch feedback {
        case let .purchased(name): return Text("\(name) is ready.")
        case .pending: return Text("Your purchase is waiting for approval. It will be delivered automatically once approved.")
        case .cancelled: return Text("You have not been charged.")
        case let .failed(message): return Text(message)
        case .restored: return Text("Any Remove Forced Ads or theme purchases on your Apple Account are now active.")
        case let .restoreFailed(message): return Text(message)
        }
    }
}

/// Five-tile preview of a theme's palette.
private struct ThemeSwatch: View {
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(palette.tiles.indices), id: \.self) { index in
                TileView(color: palette.tile(index), size: 16)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.background))
        .accessibilityHidden(true)
    }
}
