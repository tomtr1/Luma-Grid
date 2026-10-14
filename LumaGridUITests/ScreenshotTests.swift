import XCTest

/// Captures screenshots of the main screens (kept as test attachments) for visual review.
/// Also exercises tap-to-place, the accessible alternative to dragging.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testCaptureMainScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        snapshot(app, "01-Home")

        app.buttons["playButton"].tap()
        if app.buttons["Next"].waitForExistence(timeout: 3) {
            snapshot(app, "02-Tutorial")
            app.buttons["Skip"].tap()
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        snapshot(app, "03-Game-Start")

        // Tap-to-place a few pieces: select a tray piece, then tap a board cell.
        let pieces = app.buttons.matching(NSPredicate(format: "label CONTAINS 'tile piece'"))
        var placed = 0
        for row in [9, 7, 5, 3, 1] {
            guard pieces.count > 0 else { break }
            pieces.element(boundBy: 0).tap()
            let cell = app.descendants(matching: .any)["Row \(row), column 1, empty"]
            if cell.waitForExistence(timeout: 2) {
                cell.tap()
                placed += 1
            }
        }
        XCTAssertGreaterThan(placed, 0, "Expected tap-to-place to place at least one piece")
        snapshot(app, "04-Game-After-Moves")

        // Drag a piece onto the board.
        let target = app.descendants(matching: .any)["Row 5, column 6, empty"]
        if pieces.count > 0, target.exists {
            pieces.element(boundBy: 0).press(forDuration: 0.2, thenDragTo: target)
            snapshot(app, "05-Game-After-Drag")
        }

        app.buttons["Pause"].tap()
        snapshot(app, "06-Pause")
        app.buttons["Home"].tap()

        XCTAssertTrue(app.buttons["continueButton"].waitForExistence(timeout: 3))
        snapshot(app, "07-Home-Continue")

        app.buttons["Shop"].tap()
        _ = app.navigationBars["Shop"].waitForExistence(timeout: 3)
        snapshot(app, "08-Shop")
        app.buttons["Done"].tap()

        app.buttons["Settings"].tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 3)
        snapshot(app, "09-Settings")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
