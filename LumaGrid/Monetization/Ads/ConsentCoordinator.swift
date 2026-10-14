#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform)
import Foundation
import UIKit
import UserMessagingPlatform

/// Google User Messaging Platform (UMP) consent flow, following Google's current sample
/// (googleads-mobile-ios-examples, GoogleMobileAdsConsentManager). Consent is independent of
/// Apple's App Tracking Transparency; LumaGrid does not request ATT (see README > Privacy).
@MainActor
enum ConsentCoordinator {
    static var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    static var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Requests a consent-information update (every launch) and shows the consent form if
    /// required. Returns the error, if any; ads stay off unless `canRequestAds` becomes true.
    @discardableResult
    static func gatherConsent() async -> Error? {
        let parameters = RequestParameters()
        #if DEBUG
        // Launch with `-ump-debug-eea` to simulate a European user on a test device.
        if ProcessInfo.processInfo.arguments.contains("-ump-debug-eea") {
            let debugSettings = DebugSettings()
            debugSettings.geography = .EEA
            parameters.debugSettings = debugSettings
        }
        #endif

        let updateError: Error? = await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                continuation.resume(returning: error)
            }
        }
        if let updateError { return updateError }

        do {
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.lumaTopViewController)
            return nil
        } catch {
            return error
        }
    }

    static func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.lumaTopViewController)
        } catch {
            // Nothing to do: the player's previous choice remains in effect.
        }
    }
}
#endif
