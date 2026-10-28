import XCTest

/// Cheap smoke test for the in-app language switch: open Settings, pick English, and confirm a
/// label updates without restarting the app.
final class LanguageSwitchTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launch()
    }

    override func tearDown() {
        // Leave the picker back on "follow system" so other UI tests aren't affected.
        app.buttons["settings"].tap()
        let systemRow = app.buttons["lang-system"]
        if systemRow.waitForExistence(timeout: 2) { systemRow.tap() }
        app.buttons["settingsDone"].tap()
    }

    func testSwitchToEnglishUpdatesLabelsLive() {
        // "mode-拍照" is a stable identifier (set directly on the Text, no icon mixed in) that never
        // changes with the display language, so it's a reliable hook for checking the live text.
        // `.accessibilityAddTraits(.isButton)` on that Text makes XCUITest expose it as a button
        // (same reason `TourTests` queries "mode-视频" via `app.buttons`, not `app.staticTexts`).
        let photoModeLabel = app.buttons["mode-拍照"]
        XCTAssertTrue(photoModeLabel.waitForExistence(timeout: 5))

        app.buttons["settings"].tap()
        let englishRow = app.buttons["lang-en"]
        XCTAssertTrue(englishRow.waitForExistence(timeout: 5))
        englishRow.tap()
        app.buttons["settingsDone"].tap()

        XCTAssertEqual(photoModeLabel.label, "Photo")
    }
}
