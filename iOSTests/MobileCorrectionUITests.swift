import XCTest

@MainActor
final class MobileCorrectionUITests: XCTestCase {
    func testOptInFlashChoiceLiveCorrectionReviewAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["--speech-correction-fixture", "-mobileCorrectTranscript", "NO", "-autoQuickSummary", "NO"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        let setup = app.buttons["speechCorrectionSettings"]
        XCTAssertTrue(setup.waitForExistence(timeout: 30))
        setup.tap()
        let toggle = app.switches["correctSpeechToggle"].switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        wait(toggle, predicate: "value == %@", value: "1")
        app.buttons["choose-correction-model"].tap()
        let model = app.buttons["correction-model-qwen-test-flash"]
        XCTAssertTrue(model.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["correction-model-glm-test-pro"].exists)
        model.tap()
        wait(model, predicate: "label CONTAINS %@", value: "Selected")
        capture(app, "Independent Flash model selection")
        app.navigationBars["Speech correction"].buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.buttons["correctionTestPhrase"].tap()
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review-correction-")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        capture(app, "Live transcript with visible correction")
        review.tap()
        XCTAssertTrue(app.staticTexts["Please send the meeting goats to Alex."].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Please send the meeting notes to Alex."].exists)
        XCTAssertTrue(app.staticTexts["qwen-test-flash"].exists)
        capture(app, "Original wording and AI correction review")
        app.buttons["Restore original"].tap()
        wait(review, predicate: "exists == false")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Please send the meeting goats to Alex.")).firstMatch.exists)
        app.buttons["Stop listening"].tap()
    }

    private func wait(_ element: XCUIElement, predicate: String, value: String? = nil) {
        let condition = value.map { NSPredicate(format: predicate, $0) } ?? NSPredicate(format: predicate)
        let expectation = XCTNSPredicateExpectation(predicate: condition, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 30), .completed,
                       "UI state did not settle: \(predicate) on \(element)")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
