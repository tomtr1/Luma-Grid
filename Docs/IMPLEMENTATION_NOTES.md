# Implementation Notes

## Environment this was built in

The code was written in a Linux container (Ubuntu 24.04, x86_64) with no local Xcode. Verification happened in two places:
- **Locally (Docker, Swift 6.1):** `LumaGridCore` builds and its 79 tests pass.
- **GitHub Actions, `macos-26-arm64`, Xcode 26.6, iOS 26.5 simulator** (`.github/workflows/ci.yml`):
  - Release configuration build of the app (ads disabled, no credentials): **succeeded**, with no compiler warnings from LumaGrid sources.
  - Debug test run: `GameViewModelTests` (3) **passed**. UI tests `LumaGridUITests` (2) and `ScreenshotTests` (1) **passed**. The screenshot test drives Home → tutorial → game → tap-to-place → drag-and-drop → pause → Home/Continue → Shop → Settings on the simulator, and its screenshots were reviewed (this caught a shop layout bug, now fixed).
  - `StoreKitIntegrationTests` (5) **could not run** on the hosted runner: the local StoreKit test environment returned no products (`SKTestSession: Error saving configuration file`, `SKInternalErrorDomain` 3). This persisted across several attempts: format v3 and v5, a writable copy, `resetToDefaultState`, and bundling the file in the host app. The tests now **skip with that reason** when no products load. They have not passed anywhere yet; run them from Xcode on a local Mac.
- `LumaGrid.xcodeproj` is generated with XcodeGen from `project.yml`.

## Phase checklist

| Phase | Item | Status |
|---|---|---|
| 1 | Repo and toolchain inspection | Done. The repo was empty apart from `.claude/` skills. |
| 2 | Pure engine: board, placement, line clears, intersections, scoring, combos, Prism/Lumen, Pulse, tray refill, game over, seeded generation, daily seed, results, rewards | Done and tested |
| 2 | App screens: Home, Game, Results, Pause, Tutorial | Implemented, not run |
| 2 | Drag/drop with ghost preview, invalid-drop return, tap-to-place alternative | Implemented, not run |
| 3 | Clear/placement animations, Reduce Motion, haptics, original sounds, themes, accessibility labels | Implemented, not run |
| 3 | Versioned persistence, migration, corruption handling, interrupted-round resume | Done and tested (package level) |
| 4 | StoreKit 2: products, purchase states, verification, ledger, finish-after-save, updates/unfinished, restore, refund handling | Logic tested (package). StoreKit glue implemented, with SKTestSession tests not run locally |
| 5 | GMA interstitial/rewarded providers, UMP consent, frequency caps, Remove Forced Ads, single reward grant, test IDs in Debug, disabled-by-default Release | Policy tested (package). SDK glue implemented, not run |
| 6 | README, release checklist, CI, config validation script | Done |
| G | Daily challenge | Implemented: date-keyed seed, separate best, one-time bonus |

## Tests

`swift test --package-path Packages/LumaGridCore` → **79 tests, 0 failures** (run in Docker, Swift 6.1, Linux).

Coverage of the required cases:
1 empty board · 2 legal placement · 3 each edge out of bounds · 4 collision · 5 row clear · 6 column clear · 7 row+column same move · 8 intersection cleared once · 9 scoring formula · 10 combo build/reset · 11 Prism charging · 12 no double charge · 13 Pulse requires full charge · 14 Pulse clears only the 3×3 occupied cells · 15 meter consumed · 16 refill only after all three are used · 17 game over · 18 no false game over · 19 seed reproducibility (plus pinned RNG values) · 20 coin reward formula. Also: Codable round-trip continues identically, stuck-with-Pulse is not game over, 20 automated full games terminate.

Persistence: round-trip, missing save, corrupted bytes (quarantined), wrong field types, v0 → v1 migration, newer schema, negative clamping, theme entitlements and selection, settings, interrupted session, failed write keeps old data, atomic file storage.

Monetization: interstitial cadence over 9 games, 180 s gap, rolling-hour cap, clock moved backwards, pacing persistence, Remove Forced Ads, no consent → no ads, ad not loaded, reward only on earned callback, duplicate callbacks grant once, closed early, unavailable / load failure / fail to present, concurrent taps, stale callbacks, ad ID validation (Debug test-only, Release no sample IDs, missing/unexpanded values), verified vs unverified, duplicate consumable, revoked non-consumable, revoked consumable, unknown product, restore rebuilds only verified non-consumables and never touches coins.

**App-level (CI, iOS Simulator):** view-model tests and UI/screenshot tests pass (see above). StoreKit integration tests are skipped on the hosted runner.

**Not done:** physical-device play-testing, a small-iPhone layout check (CI used a single large iPhone simulator), a VoiceOver pass, loading Google test ads and showing the UMP form (ads are disabled under test launches), sandbox purchases, and a full round played to game over through the UI. Game over is covered by engine and view-model tests.

## Design decisions

- **No rotation** in v1, as the brief recommends. Each orientation is a separate weighted catalogue entry.
- **Playable-tray redraw:** when dealing a new tray, the generator redraws (up to 10 times, deterministically from the seed) until at least one piece fits. It never touches the board, and it behaves the same for every player.
- **Pulse targeting:** the first tap previews the area, a second tap inside confirms. Edge taps shift the 3×3 area onto the board. Pulse is refused (charge kept) if the area is empty. Pulse doesn't score, combo, or charge.
- **Stuck with Pulse ready** is not game over. The game prompts the player to use Pulse.
- **Tray hints:** pieces with no legal placement are dimmed. This is a strategy aid, not a rule change.
- **Daily scores** don't affect the classic best score.
- **ATT not requested** (see README > Ads). The privacy manifest covers only LumaGrid's code.
- **Swift 5 language mode for the app target** reduces strict-concurrency friction with the ObjC-based ad SDKs. The package uses Swift 6 mode.

## Known risks and remaining work

1. **StoreKit integration tests have not passed anywhere yet** (see above). The StoreKit glue in `StoreService` compiles, but real purchases have not been exercised. Run the tests locally in Xcode and test with Sandbox before release.
2. **Google Mobile Ads without an app ID:** the SDK may abort at launch if `GADApplicationIdentifier` is empty. Release builds currently ship ads disabled with an empty ID. The build phase blocks *archives* without an ID, but a local Release run might still crash. Unverified. Configure a real app ID before any Release distribution.
3. **Duplicate static linking** of `LumaGridEngine`/`LumaGridServices` into both the app and the hosted unit-test bundle may produce "class implemented in both" warnings. If types mismatch at runtime in tests, remove the package dependencies from `LumaGridTests` in `project.yml`.
4. Rewarded-ad reward callbacks are assumed to arrive before the ad's dismissal callback (Google's documented behavior). A callback after dismissal is ignored by design.
5. Local-only economy: coins don't sync across devices (disclosed in the shop).
6. Balance (piece weights, Prism frequency 14 %, scoring, coin prices) is untested with real players.
7. Localization: strings are ready for String Catalog extraction (English only). Some composed accessibility strings use `String(localized:)` with interpolation and need translator review.
8. iPad: the app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). On iPad it runs in compatibility mode.
9. App icon and sounds are simple procedurally generated originals and are good candidates for a designer's polish pass.
