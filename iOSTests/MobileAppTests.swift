import XCTest

@MainActor
final class MobileAppTests: XCTestCase {
    func testEmptySummaryExplainsDisabledActionAndSupportsRecheck() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["New"].tap()
        app.segmentedControls.buttons["Summary"].tap()
        let reason = app.staticTexts["summaryBlockReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.contains("Add notes"))
        XCTAssertFalse(app.buttons["Generate Summary"].isEnabled)
        app.buttons["Check again"].tap()
        XCTAssertTrue(app.staticTexts["sessionMessage"].label.contains("Add notes"))
    }

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
        app.secureTextFields["ollamaAPIKey"].tap()
        app.secureTextFields["ollamaAPIKey"].typeText("replacement-ui-key")
        let saveAndTest = app.buttons["Save key and test connection"]
        for _ in 0..<4 where !saveAndTest.exists { app.swipeUp() }
        XCTAssertTrue(saveAndTest.exists)
        for _ in 0..<4 where !app.buttons["Save API key"].isHittable { app.swipeDown() }
        app.buttons["Save API key"].tap()
        app.buttons["modelRole"].tap()
        app.buttons["Quick Summary"].tap()
        app.buttons["modelRole"].tap()
        app.buttons["Deep Think"].tap()
        app.buttons["Remove API key"].tap()
        XCTAssertFalse(app.staticTexts["savedAPIKey"].exists)
        app.buttons["summaryProvider"].tap()
        app.buttons["Apple Intelligence · on-device"].tap()
    }

    func testDeleteConversationAndSummaryModes() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["New"].tap()
        app.segmentedControls.buttons["Notes"].tap()
        let notes = app.textViews["Conversation notes"]
        notes.tap()
        let text = "Delete UI test " + UUID().uuidString
        notes.typeText(text)
        app.buttons["Save"].tap()
        app.segmentedControls.buttons["Summary"].tap()
        app.buttons["summaryMode"].tap()
        app.buttons["Quick Summary"].tap()
        XCTAssertTrue(app.buttons["Generate Quick Summary"].exists)
        app.buttons["summaryMode"].tap()
        app.buttons["Deep Think"].tap()
        XCTAssertTrue(app.buttons["Generate Deep Think"].exists)
        app.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete conversation"].tap()
        XCTAssertFalse(row.exists)
        app.terminate()
        app.launch()
        app.buttons["History"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists)
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
