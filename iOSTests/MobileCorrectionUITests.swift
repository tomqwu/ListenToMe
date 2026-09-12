import XCTest

@MainActor
final class MobileCorrectionUITests: XCTestCase {
    func testOptInFlashChoiceLiveCorrectionReviewAndRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["--speech-correction-fixture", "-mobileCorrectTranscript", "NO", "-autoQuickSummary", "NO"]
        app.launch()
        app.buttons["Start listening"].tap()
        let setup = app.buttons["speechCorrectionSettings"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        setup.tap()
        let toggle = app.switches["correctSpeechToggle"].switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["choose-correction-model"].tap()
        let model = app.buttons["correction-model-qwen-test-flash"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["correction-model-glm-test-pro"].exists)
        model.tap()
        XCTAssertTrue(model.label.contains("Selected"))
        capture(app, "Independent Flash model selection")
        app.navigationBars["Speech correction"].buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.buttons["correctionTestPhrase"].tap()
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review-correction-")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        capture(app, "Live transcript with visible correction")
        review.tap()
        XCTAssertTrue(app.staticTexts["Please send the meeting goats to Alex."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Please send the meeting notes to Alex."].exists)
        XCTAssertTrue(app.staticTexts["qwen-test-flash"].exists)
        capture(app, "Original wording and AI correction review")
        app.buttons["Restore original"].tap()
        XCTAssertFalse(review.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Please send the meeting goats to Alex.")).firstMatch.exists)
        app.buttons["Stop listening"].tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
