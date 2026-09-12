import XCTest

@MainActor
final class MobileIncrementalSummaryUITests: XCTestCase {
    func testListenAccumulatePublishKeepReviseAndReopenHistory() {
        let app = launch()
        app.buttons["Start listening"].tap()
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 1")
        let output = app.staticTexts["output-quick"]
        XCTAssertFalse(output.label.contains("Friday"), "A tentative discussion should accumulate without publishing")
        wait(app.staticTexts["autoQuickStatus"], contains: "Summary unchanged")
        speech("speechConcern", app: app)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 2")
        XCTAssertFalse(output.label.contains("QA"))
        speech("speechDecision", app: app)
        wait(output, contains: "Monday")
        XCTAssertTrue(output.label.contains("Sarah"))
        XCTAssertEqual(app.staticTexts["quickReadCount"].label, "Checks: 3")
        let decision = output.label
        reviewTab("Summary", app: app)
        wait(app.staticTexts["review-suggestion-summary"], contains: "confidence: high")
        XCTAssertTrue(app.staticTexts["review-suggestion-summary"].label.contains("delivery"))
        capture(app, "Evaluation suggests Summary with reason and confidence")
        app.buttons["Generate Summary"].tap()
        wait(app.staticTexts["output-summary"], contains: "reviewed")
        XCTAssertFalse(app.staticTexts["review-suggestion-summary"].exists)
        liveTab(app)
        revealQuick(app)
        capture(app, "Quick publishes a meaningful decision")
        speech("speechRepeat", app: app)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 4")
        XCTAssertEqual(output.label, decision, "A successful keep response must not rewrite visible bullets")
        wait(app.staticTexts["autoQuickStatus"], contains: "Summary unchanged")
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
        reviewTab("Deep", app: app)
        wait(app.staticTexts["review-suggestion-deep"], contains: "tradeoff")
        XCTAssertFalse(app.staticTexts["output-deep"].label.contains("reviewed"), "A recommendation must not auto-run Deep")
        capture(app, "Evaluation suggests Deep for an unresolved tradeoff")
        app.buttons["Generate Deep Summary"].tap()
        wait(app.staticTexts["output-deep"], contains: "reviewed")
        XCTAssertFalse(app.staticTexts["review-suggestion-deep"].exists)
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

    func testPartialAndSilenceDoNotPollAndAutoCanStopAnInFlightRead() {
        let app = launch(slow: true)
        app.buttons["Start listening"].tap()
        wait(app.staticTexts["autoQuickStatus"], contains: "Checking new speech")
        let toggle = app.switches["Auto Quick Summary"].switches.firstMatch
        toggle.tap()
        wait(app.staticTexts["autoQuickStatus"], contains: "Auto off")
        speech("speechDecision", app: app)
        // Longer than the delayed provider response: cancelled work cannot leak onto the screen.
        unchanged(app.staticTexts["quickReadCount"], expected: "Checks: 0", seconds: 9)
        toggle.tap()
        wait(app.staticTexts["output-quick"], contains: "Monday", timeout: 20)
        wait(app.staticTexts["quickReadCount"], contains: "Checks: 1")
        let output = app.staticTexts["output-quick"].label
        speech("speechPartial", app: app)
        unchanged(app.staticTexts["quickReadCount"], expected: "Checks: 1", seconds: 6)
        XCTAssertEqual(app.staticTexts["output-quick"].label, output)
        capture(app, "Unfinished speech does not trigger another read")
        app.buttons["Stop listening"].tap()
    }

    private func launch(slow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--incremental-summary-fixture", "-autoQuickSummary", "YES",
                               "-mobileAIProvider", "apple", "-mobileCorrectTranscript", "NO"]
        if slow { app.launchArguments.append("--incremental-slow-fixture") }
        app.launch()
        return app
    }

    private func reviewTab(_ name: String, app: XCUIApplication) {
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons[name].tap()
        } else {
            app.segmentedControls["reviewTabs"].buttons[name == "Deep" ? "Deep Summary" : name].tap()
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

    private func wait(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func unchanged(_ element: XCUIElement, expected: String, seconds: TimeInterval) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", expected), object: element)
        changed.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: seconds), .completed)
        XCTAssertEqual(element.label, expected)
    }

    private func revealQuick(_ app: XCUIApplication) {
        let output = app.staticTexts["output-quick"]
        for _ in 0..<6 where !output.isHittable {
            app.scrollViews["dashboardScroll"].swipeUp()
        }
        XCTAssertTrue(output.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
