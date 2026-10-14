import XCTest

/// Smoke test of the main flow. Launches with `-ui-testing` (in-memory save, ads and StoreKit off).
final class LumaGridUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPlayPauseAndContinueFromHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()

        // First play shows the skippable tutorial.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()

        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 3))
        app.buttons["Home"].tap()

        XCTAssertTrue(app.buttons["continueButton"].waitForExistence(timeout: 3))
    }

    func testShopAndSettingsOpenAndClose() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        app.buttons["Shop"].tap()
        XCTAssertTrue(app.navigationBars["Shop"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
    }
}
