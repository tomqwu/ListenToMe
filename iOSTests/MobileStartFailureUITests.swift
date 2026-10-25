import XCTest

@MainActor
final class MobileStartFailureUITests: XCTestCase {
    func testStartupFailureExplainsWhyListeningDidNotStart() {
        // Supported metadata does not guarantee that a subsequent asset download will succeed.
        let app = XCUIApplication()
        app.launchArguments += ["--start-failure-fixture"]
        app.launchPastReleaseNotes()
        let start = app.buttons["Start listening"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: start)
        waitForExpectations(timeout: 5)
        start.tap()
        let alert = app.alerts["Couldn’t start listening"]
        let appeared = alert.waitForExistence(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Listening startup failure on iPad"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(appeared, "A startup failure needs an actionable alert, not only a small status caption")
        guard appeared else { return }
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "could not be downloaded")).firstMatch.exists)
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
