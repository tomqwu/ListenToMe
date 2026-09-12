import XCTest

@MainActor
final class MobileNativeInteractionTests: XCTestCase {
    func testStartListeningUpdatesQuickSummaryWithoutRefreshAcrossTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "YES", "-mobileAIProvider", "apple"]
        app.launch()
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
        app.launch()
        app.buttons["Start listening"].tap()
        expect(app.staticTexts["autoQuickStatus"], containing: "Auto off")
        let output = app.staticTexts["output-quick"]
        XCTAssertFalse(output.label.contains("Thursday"))
        let toggle = app.switches["Auto Quick Summary"].switches.firstMatch
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
        app.launch()
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

    func testHistorySwipeShareAndDeleteConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launch()
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
        row.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5))
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
