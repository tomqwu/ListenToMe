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
        // The Live panel follows the latest speech, so its last line is the one sure to be on screen.
        let text = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "transcript-text-", "Marketing waits")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        for _ in 0..<3 where !text.isHittable { app.scrollViews["transcriptScroll"].swipeUp() }
        text.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Select from here"].waitForExistence(timeout: 5))
        app.buttons["Summarize from here"].tap()
        let summary = app.staticTexts["selectionSummaryText"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        wait(summary, contains: "Summary of 1 selected line.")
        XCTAssertTrue(summary.label.contains("Alex: Marketing waits"), summary.label)
        app.buttons["closeSelectionSummary"].tap()
    }

    func testSelectFromHereAndTheServerDisclosure() {
        let app = launch(["--selection-server"])
        // The full-height transcript shows every line; the Live panel may have scrolled the first ones away.
        XCTAssertTrue(app.buttons["Expand transcript"].waitForExistence(timeout: 5))
        app.buttons["Expand transcript"].tap()
        let text = app.scrollViews["expandedTranscriptScroll"].staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "transcript-text-", "We ship the beta")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Select from here"].waitForExistence(timeout: 5))
        app.buttons["Select from here"].tap()
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectionCount"].label, "3 lines selected")
        XCTAssertTrue(app.staticTexts["selectionDestination"].label.hasPrefix("Sends the selected lines to "))
        app.buttons["summarizeSelection"].tap()
        XCTAssertTrue(app.staticTexts["selectionSummaryDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["selectionSummaryDestination"].label.hasPrefix("Sends the selected lines to "))
        // Review 2: a server provider waits for the tap; the destination is on screen first.
        let send = app.buttons["startSelectionSummary"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["selectionSummaryText"].exists, "Nothing is sent before Summarize")
        capture(app, "Server provider: destination shown before Summarize")
        send.tap()
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
        app.buttons["endSelection"].tap()
        // Review 2: the touch-and-hold item is disabled too, with the reason under it.
        let text = app.scrollViews["expandedTranscriptScroll"].staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "transcript-text-", "We ship the beta")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.press(forDuration: 1.2)
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Summarize from here")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertFalse(item.isEnabled)
        XCTAssertTrue(app.buttons["Select from here"].isEnabled)
        capture(app, "Summarize from here disabled, with the reason")
    }

    /// Review 3 and 5: Cancel says "Cancelled." (not a failure); the next sheet never shows the earlier
    /// answer. The slow fixture holds each answer for two seconds.
    func testCancelAndANewSheetStartClean() {
        let app = launch(["--selection-slow"])
        app.buttons["selectTranscriptLines"].tap()
        line("We ship the beta", in: app).tap()
        app.buttons["summarizeSelection"].tap()
        let cancel = app.buttons["cancelSelectionSummary"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["selectionSummaryCancelled"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectionSummaryCancelled"].label, "Cancelled.")
        XCTAssertFalse(app.staticTexts["selectionSummaryError"].exists)
        app.buttons["restartSelectionSummary"].tap()
        wait(app.staticTexts["selectionSummaryText"], contains: "Summary of 1 selected line.", timeout: 15)
        app.buttons["closeSelectionSummary"].tap()
        line("QA signs off", in: app).tap()
        app.buttons["summarizeSelection"].tap()
        XCTAssertTrue(app.buttons["cancelSelectionSummary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["selectionSummaryText"].exists, "The earlier answer is not shown")
        wait(app.staticTexts["selectionSummaryText"], contains: "Summary of 2 selected lines", timeout: 15)
        app.buttons["closeSelectionSummary"].tap()
    }

    /// Review 4: the Live panel's sheet stays open when the layout changes mid-answer.
    func testThePanelSheetSurvivesRotation() {
        let app = launch(["--selection-slow"])
        defer { XCUIDevice.shared.orientation = .portrait }
        let text = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                        "transcript-text-", "Marketing waits")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Summarize from here"].waitForExistence(timeout: 5))
        app.buttons["Summarize from here"].tap()
        XCTAssertTrue(app.buttons["cancelSelectionSummary"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(app.staticTexts["selectionSummaryText"], contains: "Summary of 1 selected line.", timeout: 15)
        XCTAssertTrue(app.buttons["closeSelectionSummary"].exists, "The sheet is still open after rotating")
        app.buttons["closeSelectionSummary"].tap()
    }

    private func wait(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                      timeout: timeout), .completed, element.label)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
