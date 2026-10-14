import Foundation
import XCTest
import LumaGridEngine
@testable import LumaGridServices

final class PersistenceTests: XCTestCase {
    private let products = ProductIdentifiers.placeholder()

    func testSaveAndLoadRoundTrip() throws {
        let storage = InMemoryProgressStorage()
        let repository = ProgressRepository(storage: storage)
        var progress = PlayerProgress()
        progress.bestScore = 1_234
        progress.coins = 77
        progress.unlockedThemeIDs = ["tide"]
        progress.purchasedProductIDs = [products.themeNebula]
        progress.selectedThemeID = "tide"
        progress.settings.soundEnabled = false
        progress.settings.hapticsEnabled = false
        progress.tutorialCompleted = true
        progress.stats.linesCleared = 40
        progress.processedTransactionIDs = ["1001"]
        progress.adPacing.recordCompletedGame()
        try repository.save(progress)

        let (loaded, issue) = repository.load()
        XCTAssertEqual(issue, .none)
        XCTAssertEqual(loaded, progress)
    }

    func testMissingSaveYieldsDefaults() {
        let (progress, issue) = ProgressRepository(storage: InMemoryProgressStorage()).load()
        XCTAssertEqual(issue, .noSaveFound)
        XCTAssertEqual(progress, PlayerProgress())
        XCTAssertEqual(progress.selectedThemeID, ThemeCatalog.defaultThemeID)
        XCTAssertTrue(progress.settings.soundEnabled)
    }

    func testCorruptedDataResetsSafelyAndIsQuarantined() {
        for garbage in [Data("not json".utf8), Data([0xFF, 0x00, 0x13]), Data("[1,2,3]".utf8), Data()] {
            let storage = InMemoryProgressStorage(data: garbage)
            let (progress, issue) = ProgressRepository(storage: storage).load()
            XCTAssertEqual(issue, .corruptDataReset)
            XCTAssertEqual(progress, PlayerProgress())
            XCTAssertEqual(storage.quarantineCount, 1)
        }
    }

    func testWrongFieldTypesFallBackToDefaultsWhereSafe() {
        // A malformed nested settings object must not wipe the coins.
        let json = #"{"schemaVersion":1,"coins":50,"settings":"oops","stats":[1],"savedGame":{"bad":true}}"#
        let (progress, issue) = ProgressCodec.decode(Data(json.utf8))
        XCTAssertEqual(issue, .none)
        XCTAssertEqual(progress.coins, 50)
        XCTAssertEqual(progress.settings, GameSettings())
        XCTAssertNil(progress.savedGame)
    }

    func testUnversionedPrototypeSaveMigrates() {
        let json = #"{"highScore":900,"coins":12,"soundOn":false}"#
        let (progress, issue) = ProgressCodec.decode(Data(json.utf8))
        XCTAssertEqual(issue, .migrated(fromVersion: 0))
        XCTAssertEqual(progress.bestScore, 900)
        XCTAssertEqual(progress.coins, 12)
        XCTAssertFalse(progress.settings.soundEnabled)
        XCTAssertTrue(progress.settings.hapticsEnabled)
        XCTAssertEqual(progress.schemaVersion, PlayerProgress.currentSchemaVersion)
    }

    func testNewerSchemaKeepsKnownFieldsAndIgnoresUnknown() {
        let json = #"{"schemaVersion":99,"bestScore":5,"futureField":{"x":1}}"#
        let (progress, issue) = ProgressCodec.decode(Data(json.utf8))
        XCTAssertEqual(issue, .newerSchema(version: 99))
        XCTAssertEqual(progress.bestScore, 5)
    }

    func testNegativeBalancesAreClamped() {
        let (progress, _) = ProgressCodec.decode(Data(#"{"schemaVersion":1,"coins":-40,"bestScore":-1}"#.utf8))
        XCTAssertEqual(progress.coins, 0)
        XCTAssertEqual(progress.bestScore, 0)
    }

    func testThemeEntitlementsAndSelectionPersist() throws {
        let storage = InMemoryProgressStorage()
        let repository = ProgressRepository(storage: storage)
        let catalog = ThemeCatalog.standard(products: products)
        var progress = PlayerProgress()
        progress.coins = 1_000
        let tide = try XCTUnwrap(catalog.first { $0.id == "tide" })
        XCTAssertEqual(progress.unlockThemeWithCoins(tide), .unlocked)
        XCTAssertTrue(progress.selectTheme(tide))
        progress.purchasedProductIDs.insert(products.themeSunrise)
        try repository.save(progress)

        let loaded = repository.load().0
        XCTAssertTrue(loaded.isThemeUnlocked(tide))
        XCTAssertTrue(loaded.isThemeUnlocked(try XCTUnwrap(catalog.first { $0.id == "sunrise" })))
        XCTAssertFalse(loaded.isThemeUnlocked(try XCTUnwrap(catalog.first { $0.id == "nebula" })))
        XCTAssertEqual(loaded.selectedThemeID, "tide")
        XCTAssertEqual(loaded.coins, 600)
    }

    func testSettingsPersist() throws {
        let repository = ProgressRepository(storage: InMemoryProgressStorage())
        var progress = PlayerProgress()
        progress.settings.reduceMotion = true
        progress.settings.soundEnabled = false
        try repository.save(progress)
        XCTAssertEqual(repository.load().0.settings, progress.settings)
    }

    func testInterruptedSessionResumesExactly() throws {
        let repository = ProgressRepository(storage: InMemoryProgressStorage())
        var session = GameSession(seed: 77)
        let piece = try XCTUnwrap(session.tray.piece(inSlot: 0))
        try session.place(slot: 0, at: try XCTUnwrap(session.board.legalOrigins(for: piece).first))
        var progress = PlayerProgress()
        progress.savedGame = session
        try repository.save(progress)

        let restored = try XCTUnwrap(repository.load().0.savedGame)
        XCTAssertEqual(restored, session)
        XCTAssertEqual(restored.score, session.score)
        XCTAssertEqual(restored.tray, session.tray)
    }

    func testFailedWriteSurfacesErrorAndKeepsPreviousData() throws {
        let storage = InMemoryProgressStorage()
        let repository = ProgressRepository(storage: storage)
        var progress = PlayerProgress()
        progress.coins = 10
        try repository.save(progress)
        storage.failWrites = true
        progress.coins = 20
        XCTAssertThrowsError(try repository.save(progress))
        XCTAssertEqual(repository.load().0.coins, 10)
    }

    func testFileStorageWritesAtomicallyAndQuarantinesCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let storage = FileProgressStorage(fileURL: url)
        let repository = ProgressRepository(storage: storage)

        XCTAssertEqual(repository.load().1, .noSaveFound)
        var progress = PlayerProgress()
        progress.bestScore = 3
        try repository.save(progress)
        XCTAssertEqual(repository.load().0.bestScore, 3)

        try Data("{{{{".utf8).write(to: url)
        XCTAssertEqual(repository.load().1, .corruptDataReset)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("progress.corrupt.json").path))
    }

    func testRecordingAResultUpdatesBestStatsCoinsAndClearsSavedGame() {
        var progress = PlayerProgress()
        progress.bestScore = 100
        progress.savedGame = GameSession(seed: 1)
        let result = GameResult(mode: .classic, score: 450, previousBestScore: 100, linesCleared: 6,
                                bestComboStreak: 3, pulsesUsed: 1, placements: 30, coinsEarned: 9)
        let payout = progress.record(result, economy: .standard)
        XCTAssertEqual(payout, RoundPayout(roundCoins: 9, dailyBonusCoins: 0))
        XCTAssertEqual(progress.bestScore, 450)
        XCTAssertEqual(progress.coins, 9)
        XCTAssertEqual(progress.stats.gamesPlayed, 1)
        XCTAssertEqual(progress.stats.linesCleared, 6)
        XCTAssertEqual(progress.stats.bestComboStreak, 3)
        XCTAssertNil(progress.savedGame)
    }

    func testDailyBonusIsPaidOncePerDate() {
        var progress = PlayerProgress()
        let economy = EconomyConfiguration.standard
        func result(_ score: Int, _ key: String) -> GameResult {
            GameResult(mode: .daily(dateKey: key), score: score, previousBestScore: 0, linesCleared: 0,
                       bestComboStreak: 0, pulsesUsed: 0, placements: 1, coinsEarned: 5)
        }
        XCTAssertEqual(progress.record(result(200, "2026-01-01"), economy: economy).dailyBonusCoins, economy.dailyCompletionBonus)
        XCTAssertEqual(progress.record(result(300, "2026-01-01"), economy: economy).dailyBonusCoins, 0)
        XCTAssertEqual(progress.daily.bestScores["2026-01-01"], 300)
        XCTAssertEqual(progress.record(result(10, "2026-01-02"), economy: economy).dailyBonusCoins, economy.dailyCompletionBonus)
    }

    func testCoinThemeUnlockRequiresEnoughCoinsAndPurchasedThemesNeedEntitlement() throws {
        let catalog = ThemeCatalog.standard(products: products)
        let ember = try XCTUnwrap(catalog.first { $0.id == "ember" })
        let nebula = try XCTUnwrap(catalog.first { $0.id == "nebula" })
        var progress = PlayerProgress()
        progress.coins = 100
        XCTAssertEqual(progress.unlockThemeWithCoins(ember), .insufficientCoins(needed: 500))
        XCTAssertEqual(progress.coins, 100)
        XCTAssertFalse(progress.selectTheme(ember))
        XCTAssertEqual(progress.unlockThemeWithCoins(nebula), .requiresPurchase(productID: products.themeNebula))

        // A refunded purchased theme falls back to the default selection.
        progress.purchasedProductIDs.insert(products.themeNebula)
        XCTAssertTrue(progress.selectTheme(nebula))
        progress.purchasedProductIDs.removeAll()
        progress.validateSelectedTheme(in: catalog)
        XCTAssertEqual(progress.selectedThemeID, ThemeCatalog.defaultThemeID)
    }

    func testEveryThemeHasAFullPalette() {
        for theme in ThemeCatalog.standard(products: products) {
            XCTAssertEqual(theme.tiles.count, GameConfiguration.standard.paletteSize, theme.id)
        }
    }
}
