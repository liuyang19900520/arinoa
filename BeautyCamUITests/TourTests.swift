import XCTest

/// Drives the camera UI on a connected device and attaches a screenshot after each step.
/// Run with tools/ui-test.sh; screenshots are exported to tools/screens/.
final class TourTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        app.launch()
        allowSystemAlerts()
    }

    func testTour() {
        sleep(3)
        shot("01-camera")

        app.buttons["滤镜"].tap()
        sleep(1)
        shot("02-filter-panel")
        if app.staticTexts["富士"].waitForExistence(timeout: 2) {
            app.staticTexts["富士"].tap()
            sleep(1)
            shot("03-fuji")
        }
        app.buttons["滤镜"].tap()   // close the panel

        app.buttons["mode-视频"].tap()
        sleep(1)
        allowSystemAlerts()   // microphone prompt on first switch to video
        sleep(1)
        shot("04-video")
        app.buttons["aspect"].tap()
        sleep(2)
        shot("05-video-aspect-next")

        app.buttons["mode-拍照"].tap()
        sleep(2)
        app.buttons["shutter"].tap()
        sleep(3)
        allowSystemAlerts()
        shot("06-after-photo")
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Accepts camera / microphone / Photos permission prompts if they are showing.
    private func allowSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            for label in ["允许", "Allow", "允许完全访问", "Allow Full Access", "好", "OK"] {
                let b = alert.buttons[label]
                if b.exists { b.tap(); break }
            }
            sleep(1)
        }
    }
}
