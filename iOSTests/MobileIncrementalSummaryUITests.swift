import XCTest

@MainActor
final class MobileIncrementalSummaryUITests: XCTestCase {
    func testListenAccumulatePublishKeepReviseAndReopenHistory() {
        let app = launch()
        app.buttons["Start listening"].tap()
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 1")
        let output = app.staticTexts["output-quick"]
        XCTAssertFalse(output.label.contains("Friday"), "A greeting should be checked without publishing")
        wait(app.staticTexts["autoQuickStatus"], contains: "Speech checked · No takeaway yet")
        speech("speechConcern", app: app)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 2")
        XCTAssertFalse(output.label.contains("QA"))
        speech("speechDecision", app: app)
        wait(output, contains: "Monday")
        XCTAssertTrue(output.label.contains("Sarah"))
        XCTAssertEqual(app.staticTexts["quickReadCount"].label, "Checks: 3")
        let decision = output.label
        reviewTab("Summary", app: app)
        wait(app.staticTexts["output-summary"], contains: "automatically")
        capture(app, "Evaluation automatically updates Summary")
        app.buttons["Generate Summary"].tap()
        wait(app.staticTexts["output-summary"], contains: "manually")
        XCTAssertFalse(app.staticTexts["review-suggestion-summary"].exists)
        liveTab(app)
        revealQuick(app)
        capture(app, "Quick publishes a meaningful decision")
        speech("speechRepeat", app: app)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 4")
        wait(app.staticTexts["autoQuickStatus"], contains: "Summary unchanged")
        XCTAssertEqual(output.label, decision, "A successful keep response must not rewrite visible bullets")
        capture(app, "Quick retains bullets after reading repeated speech")
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        }
        speech("speechRevision", app: app)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 5")
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons["Live"].tap()
        }
        wait(output, contains: "Peter")
        XCTAssertTrue(output.label.contains("周二"))
        XCTAssertFalse(output.label.contains("Sarah"))
        XCTAssertFalse(output.label.contains("Monday"))
        XCTAssertFalse(output.label.contains("\"action\""), "Protocol JSON is never displayed")
        let corrected = output.label
        speech("speechTradeoff", app: app)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 6")
        // The fixture's evaluator recommends Deep for the tradeoff; iOS has no Deep and ignores it (#235).
        reviewTab("Summary", app: app)
        XCTAssertFalse(app.staticTexts["output-deep"].exists)
        XCTAssertFalse(app.staticTexts["review-suggestion-deep"].exists)
        XCTAssertFalse(app.buttons["Generate Deep Summary"].exists)
        capture(app, "A Deep recommendation is ignored on iOS")
        liveTab(app)
        capture(app, "Quick incorporates a Chinese decision revision")
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        app.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-record-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        wait(output, contains: "Peter")
        XCTAssertEqual(output.label, corrected, "The last published result survives opening History")
    }

    func testFirstTopicAndQuestionPublishWithoutWaitingForDecision() {
        let app = launch()
        app.buttons["Start listening"].tap()
        wait(app.staticTexts["autoQuickStatus"], contains: "Speech checked · No takeaway yet")
        speech("speechTopic", app: app)
        wait(app.staticTexts["output-quick"], contains: "Azure")
        reviewTab("Summary", app: app)
        wait(app.staticTexts["output-summary"], contains: "automatically")
        liveTab(app)
        speech("speechQuestion", app: app)
        wait(app.staticTexts["output-quick"], contains: "APM")
        XCTAssertLessThanOrEqual(app.staticTexts["output-quick"].label.count, 480)
        capture(app, "First topic and unanswered question are visible without any decision")
        reviewTab("Summary", app: app)
        app.buttons["Generate Summary"].tap()
        wait(app.staticTexts["output-summary"], contains: "manually")
        XCTAssertFalse(app.staticTexts["output-deep"].exists, "No Deep pane on iOS (#235)")
        liveTab(app)
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.staticTexts["output-quick"].label.contains("APM"))
    }

    func testShortPartialAndSilenceDoNotPollAndAutoCanStopAnInFlightRead() {
        let app = launch(slow: true)
        app.buttons["Start listening"].tap()
        wait(app.staticTexts["autoQuickStatus"], contains: "Checking new speech")
        let toggle = app.switches["Auto summaries"].switches.firstMatch
        toggle.tap()
        wait(app.staticTexts["autoQuickStatus"], contains: "Auto off")
        speech("speechDecision", app: app)
        // Longer than the delayed provider response: cancelled work cannot leak onto the screen.
        unchanged(app.staticTexts["quickReadCount"], expected: "Checks: 0", seconds: 9)
        toggle.tap()
        wait(app.staticTexts["output-quick"], contains: "Monday", timeout: 30)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 1")
        let output = app.staticTexts["output-quick"].label
        speech("speechPartial", app: app)
        unchanged(app.staticTexts["quickReadCount"], expected: "Checks: 1", seconds: 6)
        XCTAssertEqual(app.staticTexts["output-quick"].label, output)
        capture(app, "Unfinished speech does not trigger another read")
        app.buttons["Stop listening"].tap()
    }

    func testLiveRecognitionPublishesBeforeFinalAndStatusShowsEventFlow() {
        let app = launch()
        app.buttons["Start listening"].tap()
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 1")
        speech("speechLiveDecision", app: app)
        wait(app.staticTexts["output-quick"], contains: "Monday")
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 2")
        app.buttons["quickStatusDetails"].tap()
        let details = app.alerts["Quick Summary status"]
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        XCTAssertTrue(details.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Speech events: 2 (final: 1)")).firstMatch.exists)
        capture(app, "Live speech reaches scheduler and model before final recognition")
        details.buttons["Close"].tap()
        unchanged(app.staticTexts["quickReadCount"], expected: "Checks: 2", seconds: 6)
        speech("speechRevision", app: app)
        wait(app.staticTexts["output-quick"], contains: "Peter")
        XCTAssertFalse(app.staticTexts["output-quick"].label.contains("Monday"))
        capture(app, "Final recognition replaces provisional Quick wording")
        app.buttons["Stop listening"].tap()
    }

    func testLongConversationShowsQuickBeforeBacklogFinishesWithoutRefresh() {
        let app = launch(backlog: true)
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["backgroundRecordingNotice"].exists)
        revealQuick(app)
        wait(app.staticTexts["output-quick"], contains: "Monday")
        XCTAssertTrue(app.staticTexts["output-quick"].label.contains("Sarah"))
        XCTAssertTrue(app.staticTexts["autoQuickStatus"].label.contains("Catching up"))
        XCTAssertLessThanOrEqual(app.staticTexts["output-quick"].label.count, 480)
        capture(app, "Quick visible while long conversation is still being processed")
        app.buttons["Stop listening"].tap()
    }

    func testManualSummaryIncludesLiveRecognitionAndDropsMarkerAfterFinalization() {
        let app = XCUIApplication()
        app.launchArguments = ["--incremental-summary-fixture", "-autoQuickSummary", "NO",
                               "-mobileAIProvider", "apple", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["backgroundRecordingNotice"].exists)
        speech("speechLiveDecision", app: app)
        reviewTab("Summary", app: app)
        app.buttons["Generate Summary"].tap()
        wait(app.staticTexts["output-summary"], contains: "Recognition is provisional.")
        capture(app, "Manual Summary includes tagged live recognition")
        speech("speechDecision", app: app)
        reviewTab("Summary", app: app)
        app.buttons["Generate Summary"].tap()
        let finalized = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)",
                                   "reviewed manually.", "Recognition is provisional."),
            object: app.staticTexts["output-summary"])
        XCTAssertEqual(XCTWaiter.wait(for: [finalized], timeout: 15), .completed)
        capture(app, "Manual Summary removes provisional guidance after final recognition")
        app.buttons["Stop listening"].tap()
    }

    private func launch(slow: Bool = false, backlog: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--incremental-summary-fixture", "-autoQuickSummary", "YES",
                               "-mobileAIProvider", "apple", "-mobileCorrectTranscript", "NO"]
        if slow { app.launchArguments.append("--incremental-slow-fixture") }
        if backlog { app.launchArguments.append("--incremental-backlog-fixture") }
        app.launchPastReleaseNotes()
        return app
    }

    /// The phone shows Summary on its own page; a wide layout shows it beside Live.
    private func reviewTab(_ name: String, app: XCUIApplication) {
        let tabs = app.segmentedControls["workspaceTabs"]
        if tabs.exists {
            let target = tabs.buttons[name]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in target.isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
            if !target.isSelected { target.tap() }
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in target.isSelected }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed,
                           "The requested workspace must actually be selected before using its controls")
        }
        if name == "Summary" {
            let generate = app.buttons["Generate Summary"]
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in generate.isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        }
    }

    private func liveTab(_ app: XCUIApplication) {
        if app.segmentedControls["workspaceTabs"].exists { app.segmentedControls["workspaceTabs"].buttons["Live"].tap() }
    }

    private func speech(_ identifier: String, app: XCUIApplication) {
        app.buttons["testSpeechMenu"].tap()
        // Large Dynamic Type makes the native fixture menu scroll; its final row is initially unmounted.
        for _ in 0..<4 where !app.buttons[identifier].exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        app.buttons[identifier].tap()
    }

    private func wait(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 30) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected \(text) in \(element); last label: \(element.label)")
    }

    private func unchanged(_ element: XCUIElement, expected: String, seconds: TimeInterval) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", expected), object: element)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: seconds), .completed)
        XCTAssertEqual(element.label, expected)
    }

    private func revealQuick(_ app: XCUIApplication) {
        let output = app.staticTexts["output-quick"]
        XCTAssertTrue(output.waitForExistence(timeout: 3))
        for _ in 0..<6 where !output.isHittable {
            let dashboard = app.scrollViews["dashboardScroll"]
            if dashboard.exists { dashboard.swipeUp() }
            else {
                let readingArea = app.otherElements["summary-panel-quick"].scrollViews.firstMatch
                XCTAssertTrue(readingArea.exists, "Scroll the Quick panel in fixed portrait/wide layouts")
                guard readingArea.exists else { break }
                readingArea.swipeUp()
            }
        }
        XCTAssertTrue(output.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
