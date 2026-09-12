import XCTest

@MainActor
final class MobileCalendarUITests: XCTestCase {
    private func openCalendar(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        app.buttons["Import from Calendar"].tap()
        XCTAssertTrue(app.navigationBars["Import from Calendar"].waitForExistence(timeout: 5))
        if app.buttons["connectCalendar"].waitForExistence(timeout: 2) {
            app.buttons["connectCalendar"].tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Full Access"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
        }
    }

    func testCalendarPermissionAndDatePicker() {
        let app = XCUIApplication()
        app.launch()
        openCalendar(app)
        XCTAssertTrue(app.datePickers["calendarDate"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Refresh events"].exists)
        app.buttons["Done"].tap()
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.buttons["Import from Calendar"].exists)
    }

    func testImportStagedEventThroughPreviewIntoNotes() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        app.textViews["Conversation notes"].tap()
        app.textViews["Conversation notes"].typeText("Existing user notes.")
        app.buttons["Done"].tap()
        openCalendar(app)
        let event = app.buttons["calendar-event-ListenToMe Calendar UI Test"]
        guard event.waitForExistence(timeout: 5) else { throw XCTSkip("Requires the local EventKit fixture.") }
        event.tap()
        let preview = app.staticTexts["calendarEventPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.contains("Test room"))
        XCTAssertTrue(preview.label.contains("https://example.com/calendar-test"))
        app.buttons["importCalendarEvent"].tap()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5))
        app.buttons["Notes"].tap()
        let notes = app.textViews["Conversation notes"]
        let text = notes.value as? String ?? ""
        XCTAssertTrue(text.hasPrefix("Existing user notes."))
        XCTAssertTrue(text.contains("Calendar import acceptance fixture."))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Imported calendar context"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Done"].tap()
        app.terminate(); app.launch()
        XCTAssertEqual(app.textFields["conversationTitle"].value as? String, "ListenToMe Calendar UI Test")
        app.buttons["Notes"].tap()
        XCTAssertEqual(app.textViews["Conversation notes"].value as? String, text)
    }
}
