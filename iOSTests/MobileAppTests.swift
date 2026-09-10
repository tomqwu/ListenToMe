import XCTest

@MainActor
final class MobileAppTests: XCTestCase {
    func testMicrophoneDenialKeepsAppIdleAndRetryDoesNotReprompt() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()
        app.buttons["Start listening"].tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Don’t Allow"].tap()
        let message = app.staticTexts["sessionMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Microphone access is off"))
        XCTAssertTrue(app.buttons["Start listening"].isEnabled)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        app.buttons["Start listening"].tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertFalse(alert.exists)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
    }

    func testNotesSurviveNewConversationAndRelaunch() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["New"].tap()
        app.segmentedControls.buttons["Notes"].tap()
        let notes = app.textViews["Conversation notes"]
        notes.tap()
        notes.typeText("Decision: review the mobile release on Friday.")
        app.buttons["Save"].tap()
        app.buttons["New"].tap()
        app.terminate()
        app.launch()
        app.segmentedControls.buttons["Notes"].tap()
        XCTAssertEqual(app.textViews["Conversation notes"].value as? String, "")
        app.buttons["History"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Decision: review the mobile release")).firstMatch.tap()
        app.segmentedControls.buttons["Notes"].tap()
        XCTAssertTrue((notes.value as? String ?? "").contains("review the mobile release"))
        app.terminate()
        app.launch()
        app.segmentedControls.buttons["Notes"].tap()
        XCTAssertTrue((app.textViews["Conversation notes"].value as? String ?? "").contains("review the mobile release"))
        app.buttons["Settings"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["iPhone & iPad · iOS 26 or later"].waitForExistence(timeout: 3))
    }
}
