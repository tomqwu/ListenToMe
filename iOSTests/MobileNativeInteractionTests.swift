import XCTest

@MainActor
final class MobileNativeInteractionTests: XCTestCase {
    func testStartListeningUpdatesQuickSummaryWithoutRefreshAcrossTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "YES", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        let output = app.staticTexts["output-quick"]
        expect(output, containing: "Thursday")
        XCTAssertTrue(app.buttons["Stop listening"].isEnabled)
        capture(app, "Automatic Quick Summary while listening")
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        }
        app.buttons["nextTestPhrase"].tap()
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons["Live"].tap()
        }
        expect(output, containing: "Alex")
        expect(app.staticTexts["autoQuickStatus"], containing: "Up to date")
        capture(app, "Automatic catch-up after new speech")
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        XCTAssertTrue(output.label.contains("Alex"))
    }

    func testAutoIsOptInAndCanBeDisabledWhileListening() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        expect(app.staticTexts["autoQuickStatus"], containing: "Auto off")
        let output = app.staticTexts["output-quick"]
        XCTAssertFalse(output.label.contains("Thursday"))
        let toggle = app.switches["Auto summaries"].switches.firstMatch
        toggle.tap()
        expect(output, containing: "Thursday")
        toggle.tap()
        app.buttons["nextTestPhrase"].tap()
        expect(app.staticTexts["autoQuickStatus"], containing: "Auto off")
        XCTAssertFalse(output.label.contains("Alex"))
        app.buttons["Stop listening"].tap()
    }

    func testAutomaticFailureIsVisibleAndRetriesWithoutRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "--automatic-failure-fixture",
                               "-autoQuickSummary", "YES", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        let error = app.staticTexts["quickSummaryError"]
        XCTAssertTrue(error.waitForExistence(timeout: 4))
        XCTAssertTrue(error.isHittable)
        let panel = app.otherElements["summary-panel-quick"].firstMatch
        XCTAssertLessThanOrEqual(error.frame.maxY, panel.frame.maxY)
        XCTAssertTrue(error.label.contains("internet connection was lost"))
        capture(app, "Automatic summary failure and retry status")
        expect(app.staticTexts["output-quick"], containing: "Thursday")
        XCTAssertFalse(app.staticTexts["quickSummaryError"].exists)
        app.buttons["Stop listening"].tap()
    }

    func testBottomSaveConfirmsPersistenceAndShareCopiesReadableText() {
        let app = XCUIApplication()
        app.launchArguments = ["-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["New"].tap()
        let marker = "Readable share " + UUID().uuidString
        app.textFields["conversationTitle"].tap()
        app.textFields["conversationTitle"].typeText(marker)
        app.buttons["Notes"].tap()
        app.textViews["Conversation notes"].tap()
        app.textViews["Conversation notes"].typeText("## Decision\n- **Alex** owns the Friday review.")
        app.buttons["Done"].tap()
        app.buttons["Save"].tap()
        let feedback = app.staticTexts["saveFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(feedback.isHittable)
        XCTAssertTrue(feedback.label.contains("Saved to History"))
        capture(app, "Bottom Save confirms local History storage")
        app.terminate(); app.launchPastReleaseNotes()
        app.buttons["History"].tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                     "history-record-", marker)).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        app.buttons["More"].tap()
        app.buttons["Share"].tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.tap()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        app.buttons["Paste"].tap()
        let text = app.textViews["Conversation notes"].value as? String ?? ""
        XCTAssertTrue(text.contains(marker))
        XCTAssertTrue(text.contains("Alex owns the Friday review."))
        XCTAssertFalse(text.contains("## Decision"))
        XCTAssertFalse(text.contains("**Alex**"))
        capture(app, "Share Copy contains readable text without Markdown markers")
        app.buttons["Done"].tap()
    }

    func testHistorySwipeShareAndDeleteConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-record-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeRight()
        XCTAssertTrue(app.buttons["Share"].isHittable)
        capture(app, "History swipe right to share")
        app.buttons["Share"].tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "Native conversation share sheet")
        copy.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].isHittable)
        capture(app, "History swipe left to delete")
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.alerts["Delete conversation?"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
        // Finish the swipe/alert interaction before exercising a fresh context-menu gesture.
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 2)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 10))
        app.buttons["Delete"].tap()
        app.buttons["Delete conversation"].tap()
        XCTAssertTrue(app.staticTexts["No saved conversations"].waitForExistence(timeout: 5))
        capture(app, "History empty after confirmed deletion")
    }

    private func expect(_ element: XCUIElement, containing text: String) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 10), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
