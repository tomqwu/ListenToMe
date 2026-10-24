import XCTest

/// Issue #234: Select mode, long-press Summarize from here, and the selection summary sheet.
@MainActor
final class MobileSelectionSummaryUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--selection-summary-fixture", "-autoQuickSummary", "NO"] + extra
        app.launchPastReleaseNotes()
        return app
    }

    private func line(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "select-line-", text))
            .firstMatch
    }

    func testSelectLinesSummarizeAndAddToNotes() {
        let app = launch()
        let select = app.buttons["selectTranscriptLines"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "0 lines selected")
        XCTAssertFalse(app.buttons["summarizeSelection"].isEnabled, "Nothing selected yet")
        line("We ship the beta", in: app).tap()
        line("QA signs off", in: app).tap()
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "2 lines selected")
        XCTAssertTrue(app.staticTexts["selectionDestination"].label.contains("on this device"))
        capture(app, "Two lines selected")
        app.buttons["summarizeSelection"].tap()
        let text = app.staticTexts["selectionSummaryText"]
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        wait(text, contains: "Summary of 2 selected lines")
        XCTAssertTrue(text.label.contains("Alex: We ship the beta on Friday."), text.label)
        XCTAssertEqual(app.staticTexts["selectionSpan"].label, "1:02–1:15 · 2 lines")
        XCTAssertTrue(app.buttons["copySelectionSummary"].exists)
        XCTAssertTrue(app.buttons["shareSelectionSummary"].exists)
        capture(app, "Selection summary sheet")
        app.buttons["addSelectionSummaryToNotes"].tap()
        app.buttons["closeSelectionSummary"].tap()
        app.buttons["endSelection"].tap()
        XCTAssertFalse(app.buttons["summarizeSelection"].exists)
        XCTAssertTrue(app.buttons["selectExpandedTranscriptLines"].exists, "Select is offered again")
        app.navigationBars["Transcript"].buttons["Done"].tap()
        app.buttons["Notes"].tap()
        let notes = app.textViews["Conversation notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        XCTAssertTrue((notes.value as? String ?? "").contains("Selection summary (1:02–1:15 · 2 lines)"))
        app.buttons["Done"].tap()
        // The summary is kept with the conversation and listed under its Summary.
        if app.segmentedControls["workspaceTabs"].exists { app.segmentedControls["workspaceTabs"].buttons["Summary"].tap() }
        let saved = app.descendants(matching: .any).matching(identifier: "savedSelectionSummaries").firstMatch
        for _ in 0..<4 where !saved.exists || !saved.isHittable { app.swipeUp() }
        XCTAssertTrue(saved.exists)
        capture(app, "Saved selection summaries under the Summary")
    }

    func testLongPressSummarizesFromThatLine() {
        let app = launch()
        let text = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "transcript-text-", "QA signs off")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Select from here"].waitForExistence(timeout: 5))
        app.buttons["Summarize from here"].tap()
        let summary = app.staticTexts["selectionSummaryText"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        wait(summary, contains: "Summary of 2 selected lines")
        XCTAssertTrue(summary.label.contains("Sam: QA signs off"), summary.label)
        app.buttons["closeSelectionSummary"].tap()
    }

    func testSelectFromHereAndTheServerDisclosure() {
        let app = launch(["--selection-server"])
        let text = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "transcript-text-", "We ship the beta")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.press(forDuration: 1.2)
        app.buttons["Select from here"].tap()
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "3 lines selected")
        XCTAssertTrue(app.staticTexts["selectionDestination"].label.hasPrefix("Sends the selected lines to "))
        app.buttons["summarizeSelection"].tap()
        XCTAssertTrue(app.staticTexts["selectionSummaryDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["selectionSummaryDestination"].label.hasPrefix("Sends the selected lines to "))
        wait(app.staticTexts["selectionSummaryText"], contains: "Summary of 3 selected lines")
        app.buttons["closeSelectionSummary"].tap()
    }

    func testAnUnavailableProviderDisablesSummarizeWithTheReason() {
        let app = launch(["--selection-unavailable"])
        app.buttons["selectTranscriptLines"].tap()
        line("We ship the beta", in: app).tap()
        XCTAssertFalse(app.buttons["summarizeSelection"].isEnabled)
        XCTAssertTrue(app.staticTexts["selectionBlockReason"].exists)
        capture(app, "Summarize selection unavailable, with the reason")
    }

    private func wait(_ element: XCUIElement, contains text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                      timeout: 10), .completed, element.label)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
