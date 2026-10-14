# App Store Release Checklist

These tasks need human accounts, legal judgement, real devices, or outside services. None of them have been done yet. Following this list does not guarantee App Review approval; check Apple's and Google's current policies at submission time.

## 1. Identity and legal
- [ ] Choose the final name. Check App Store name availability, domain availability, and trademarks for "LumaGrid" or the replacement name. This has not been checked.
- [ ] Update `LUMA_DISPLAY_NAME`, `LUMA_BUNDLE_ID`, `LUMA_PRODUCT_ID_PREFIX` (in `Config/Secrets.xcconfig` or `Config/Base.xcconfig`), the tagline in `LogoLockup` (`DesignSystem/Components.swift`), and the product IDs in `LumaGrid/Resources/LumaGrid.storekit`.
- [ ] Set `DEVELOPMENT_TEAM` and confirm automatic signing works for device builds.
- [ ] Publish a real **privacy policy** and **support page**, then set `LUMA_PRIVACY_POLICY_URL` / `LUMA_SUPPORT_URL` (written as `https:/$()/…` in xcconfig). The app hides these links until they're set. Do not submit with placeholder URLs.
- [ ] Have someone review the privacy policy against the data the Google SDKs collect (see section 4).
- [ ] Optional: review the icon, colors, and UI for any unintended resemblance to existing games.

## 2. App Store Connect
- [ ] Create the app record with the final bundle ID, primary category Games → Puzzle, and age rating questionnaire. Ads and IAPs are present; this is not designed for the Kids Category. If you target children, reassess ads, IAP, parental gates, and privacy first.
- [ ] Create the in-app purchases with exactly these IDs (prefix = `LUMA_PRODUCT_ID_PREFIX`):
  - [ ] `<prefix>.removeforcedads`: Non-Consumable. Description must say that forced ads between games are removed **and that optional rewarded ads remain available**.
  - [ ] `<prefix>.theme.nebula`: Non-Consumable
  - [ ] `<prefix>.theme.sunrise`: Non-Consumable
  - [ ] `<prefix>.coins.small`: Consumable (500 coins)
  - [ ] `<prefix>.coins.large`: Consumable (1,500 coins)
  - [ ] Each needs a localized display name, description, price, and review screenshot. Submit them with the first app version.
- [ ] Sign the Paid Applications agreement and fill in banking and tax details. Products won't load without it.
- [ ] Test purchases with Sandbox testers on a physical device: purchase, cancel, Ask to Buy (pending), refund/revocation, Restore Purchases after reinstall, and interrupted purchase (kill the app mid-purchase, relaunch, confirm a single coin grant).
- [ ] App Privacy questionnaire: answer from Xcode's privacy report (Product → Archive → Generate Privacy Report), which includes Google Mobile Ads/UMP manifests. Expect disclosures such as device ID / advertising data, product interaction, diagnostics, and coarse location used by the ad SDK. Verify against Google's current data-disclosure guidance.
- [ ] App Review notes: explain that interstitials appear only between rounds with frequency caps, that rewarded ads are optional and grant 50 coins after completion, that Remove Forced Ads removes interstitials only, that coins are local to the device, and that there is no login.
- [ ] Screenshots (6.9" and 6.5" iPhone at minimum, per current requirements), app description, keywords, support URL, marketing URL (optional), and copyright.
- [ ] Do not claim affiliation with Apple, Google, or any other game.

## 3. Google AdMob and consent
- [ ] Create an AdMob account and the iOS app, then create one **Interstitial** and one **Rewarded** ad unit. For the rewarded unit, the reward amount shown to users is LumaGrid's own fixed 50 coins; the app ignores the AdMob-configured amount.
- [ ] Put the IDs in `Config/Secrets.xcconfig` for Release only (see `Secrets.example.xcconfig`), with `LUMA_ADS_ENABLED[config=Release] = YES`. Debug builds must keep Google's test IDs.
- [ ] Register your test devices in AdMob, or rely on Debug test IDs. Never click your own live ads.
- [ ] In AdMob **Privacy & messaging**, create and publish a GDPR (EEA/UK/Switzerland) message, plus a US state regulations message if you serve those regions. Test with `-ump-debug-eea` on a registered test device.
- [ ] Add an `app-ads.txt` file to the developer website listed in App Store Connect.
- [ ] Refresh `SKAdNetworkItems` in `Info.plist` from Google's current list (and any mediation partners' lists).
- [ ] Decide on ATT. The default is no ATT prompt, so no IDFA. If you enable it: add `NSUserTrackingUsageDescription`, show an honest explanation before the system prompt, honor denial, and update App Privacy answers.
- [ ] Re-check current EEA/UK and US privacy requirements before launch.
- [ ] Confirm the Release archive passes the **Validate Release Configuration** build phase (real app ID, no sample IDs).

## 4. Quality on real hardware
- [ ] Play complete rounds on at least one small iPhone (e.g. SE / mini class) and one large iPhone. Check drag precision, ghost preview, invalid-drop return, Pulse targeting, and safe areas around the Dynamic Island and home indicator.
- [ ] VoiceOver: complete a round using tap-to-place only. Check Dynamic Type at large sizes on Home, Shop, and Settings.
- [ ] Reduce Motion on/off, sound and haptics toggles, silent switch.
- [ ] Interruptions: incoming call, backgrounding mid-drag, force-quit mid-round → Continue from Home restores the exact board.
- [ ] Airplane mode: the full game works, the shop shows its unavailable state, and no ads appear without blocking anything.
- [ ] Ads with live IDs on a TestFlight build: interstitial cadence (none in first 2 games, then ≥3 games and ≥180 s apart, ≤3/hour), never during play or pause; rewarded grant once; Remove Forced Ads stops interstitials.
- [ ] Balance pass: tune `GenerationRules.prismChance`, piece weights, scoring, and coin payouts after playtesting.
- [ ] Run the full test suite (`xcodebuild test …`) and fix any warnings from the latest Xcode.

## 5. Submission
- [ ] Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
- [ ] Archive the Release configuration, validate, upload, and distribute to TestFlight first.
- [ ] Submit the IAPs together with the build.
