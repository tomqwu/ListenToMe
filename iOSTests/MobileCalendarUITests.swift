import XCTest

@MainActor
final class MobileCalendarUITests: XCTestCase {
    private func openCalendar(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        app.buttons["Import from Calendar"].tap()
        XCTAssertTrue(app.navigationBars["Import from Calendar"].waitForExistence(timeout: 5))
        if app.buttons["connectCalendar"].waitForExistence(timeout: 2) {
            app.buttons["connectCalendar"].tap()
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts
                .matching(NSPredicate(format: "label CONTAINS[c] 'Calendar'")).firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "Expected Calendar permission prompt")
            // The approval label differs between iOS simulator runtime versions.
            let allow = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Allow'")).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 5), alert.debugDescription)
            if allow.exists { allow.tap() }
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
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        let importButton = app.buttons["Import from Calendar"]
        let form = app.collectionViews.firstMatch
        for _ in 0..<4 where !importButton.exists || !importButton.isHittable {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.3)))
        }
        XCTAssertTrue(importButton.isHittable)
        importButton.tap()
        XCTAssertTrue(app.datePickers["calendarDate"].waitForExistence(timeout: 5))
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
