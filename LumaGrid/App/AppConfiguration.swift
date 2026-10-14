import Foundation
import LumaGridEngine
import LumaGridServices

/// Central configuration. Build-specific values (bundle ID, ad IDs, URLs, product prefix) come
/// from Config/*.xcconfig through Info.plist; gameplay and economy tuning lives in the
/// LumaGridCore configuration types referenced here.
enum AppConfiguration {
    // MARK: Build

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// True for UI-test launches (`-ui-testing`) and when hosting unit tests: in-memory save
    /// data, no ads, and no StoreKit listeners, so tests never touch real progress.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var displayName: String {
        info("CFBundleDisplayName") ?? "LumaGrid"
    }

    static var versionDescription: String {
        let version = info("CFBundleShortVersionString") ?? "?"
        let build = info("CFBundleVersion") ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: Gameplay & economy

    static let game = GameConfiguration.standard
    static let economy = EconomyConfiguration.standard
    static let interstitialPolicy = InterstitialPolicy.standard

    // MARK: Store

    static var productIdentifiers: ProductIdentifiers {
        let prefix = info("LumaProductIDPrefix") ?? ""
        return .placeholder(namespace: prefix.isEmpty ? "com.example.lumagrid" : prefix)
    }

    static let productCatalog = ProductCatalog(identifiers: productIdentifiers)
    static let themes = ThemeCatalog.standard(products: productIdentifiers)

    // MARK: Ads

    static var ads: AdsConfiguration {
        AdsConfiguration(
            applicationID: info("GADApplicationIdentifier") ?? "",
            interstitialUnitID: info("LumaInterstitialAdUnitID") ?? "",
            rewardedUnitID: info("LumaRewardedAdUnitID") ?? "",
            isDebugBuild: isDebugBuild,
            isEnabledInBuild: (info("LumaAdsEnabled") ?? "NO").uppercased() == "YES" && !isUITesting
        )
    }

    // MARK: Links (hidden in the UI until real URLs are configured)

    static var privacyPolicyURL: URL? { publicURL("LumaPrivacyPolicyURL") }
    static var supportURL: URL? { publicURL("LumaSupportURL") }

    // MARK: Helpers

    private static func info(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    private static func publicURL(_ key: String) -> URL? {
        guard
            let string = info(key),
            let url = URL(string: string),
            url.scheme == "https",
            let host = url.host, !host.isEmpty,
            !host.hasSuffix("example.com"), !host.hasSuffix("example.org"), !host.hasSuffix(".example")
        else { return nil }
        return url
    }
}
