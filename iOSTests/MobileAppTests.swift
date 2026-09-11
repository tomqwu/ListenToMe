import XCTest

@MainActor
final class MobileAppTests: XCTestCase {
    func testOllamaSettingsKeyPersistenceAndRemoval() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["summaryProvider"].tap()
        app.buttons["Ollama Cloud"].tap()
        let field = app.secureTextFields["ollamaAPIKey"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("synthetic-ui-test-key")
        app.buttons["Save API key"].tap()
        XCTAssertTrue(app.staticTexts["savedAPIKey"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["savedAPIKey"].waitForExistence(timeout: 3))
        app.buttons["Remove API key"].tap()
        XCTAssertFalse(app.staticTexts["savedAPIKey"].exists)
        app.buttons["summaryProvider"].tap()
        app.buttons["Apple Intelligence · on-device"].tap()
    }

    func testSimulatorExplainsUnavailableSpeechWithoutRequestingMicrophone() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()
        app.buttons["Start listening"].tap()
        let message = app.staticTexts["sessionMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("Live transcription is unavailable in the iPhone simulator"))
        XCTAssertTrue(message.label.contains("physical iPhone or iPad"))
        XCTAssertTrue(message.label.contains("Microphone permission will not fix this"))
        XCTAssertTrue(app.buttons["Start listening"].isEnabled)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertFalse(alert.exists)
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
        let release = app.staticTexts["iPhone & iPad · iOS 26 or later"]
        for _ in 0..<5 where !release.isHittable { app.swipeUp() }
        XCTAssertTrue(release.isHittable)
    }
}
