import XCTest

@MainActor
final class MobileStartFailureUITests: XCTestCase {
    func testStartupFailureExplainsWhyListeningDidNotStart() {
        // Given the simulator cannot prepare live transcription, when listening is requested,
        // then the failure must be prominent rather than looking like an unresponsive button.
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        let alert = app.alerts["Couldn’t start listening"]
        let appeared = alert.waitForExistence(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Listening startup failure on iPad"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(appeared, "A startup failure needs an actionable alert, not only a small status caption")
        guard appeared else { return }
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "simulator")).firstMatch.exists)
        XCTAssertTrue(alert.buttons["Recording settings"].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["Start listening"].isEnabled)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        app.buttons["Start listening"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Retry must show a fresh failure rather than silently return")
        alert.buttons["Recording settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
