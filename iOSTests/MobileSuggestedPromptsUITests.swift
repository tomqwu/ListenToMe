import XCTest

/// Context-aware "Suggested" chips (#61) through the real Start path with the synthetic-speech
/// fixture: the chips arrive with the Auto Quick decision, fit the phone width, and a tap is answered
/// in the Ask card under Quick.
@MainActor
final class MobileSuggestedPromptsUITests: XCTestCase {
    func testChipsArriveWithAutoFitThePhoneAndATapAnswersUnderQuick() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "YES", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        expect(app.staticTexts["output-quick"], containing: "Thursday")
        let chip = app.buttons["suggestedPrompt-0"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.label, "Who owns the Thursday review?")
        let second = app.buttons["suggestedPrompt-1"]
        XCTAssertEqual(second.label, "Draft a reminder for Thursday")
        let window = app.windows.firstMatch.frame
        for element in [chip, second] {
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX, "A chip must not overflow the screen")
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX, "A chip must not overflow the screen")
            XCTAssertGreaterThanOrEqual(element.frame.height, 44, "A chip is a full-size tap target")
        }
        capture(app, "Suggested chips under the Quick Summary")

        chip.tap()
        let answer = app.staticTexts["suggestedAnswer"]
        expect(answer, containing: "Nobody has claimed the Thursday review")
        XCTAssertEqual(app.staticTexts["suggestedQuestion"].label, "Who owns the Thursday review?",
                       "The answer sits under what was asked, in the Ask card under Quick")
        XCTAssertTrue(app.staticTexts["output-quick"].label.contains("Thursday"), "Quick Summary is unchanged")
        XCTAssertFalse(app.staticTexts["output-quick"].label.contains("Nobody has claimed"))
        if app.segmentedControls["workspaceTabs"].exists {
            XCTAssertTrue(app.segmentedControls["workspaceTabs"].buttons["Live"].isSelected, "A tap stays on Live")
        }
        capture(app, "Ask card under Quick Summary")
        let remaining = app.buttons["suggestedPrompt-0"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertEqual(remaining.label, "Draft a reminder for Thursday", "A chip that was answered leaves the row")
        app.buttons["closeSuggestedAsk"].tap()
        XCTAssertFalse(app.staticTexts["suggestedAnswer"].waitForExistence(timeout: 2), "Close dismisses the card")
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["suggestedPrompt-0"].exists, "Stop keeps chips: the conversation is still askable")
    }

    func testNoChipsWhileAutoIsOff() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        expect(app.staticTexts["autoQuickStatus"], containing: "Auto off")
        XCTAssertFalse(app.buttons["suggestedPrompt-0"].waitForExistence(timeout: 4),
                       "With Auto off no pass runs, so no chip is made")
        app.buttons["Stop listening"].tap()
    }

    private func expect(_ element: XCUIElement, containing text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 10), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
