import XCTest

/// The domain-vocabulary suggestion banner and "Add to My terms" (issue #222), with a fixture recorder
/// that reports the contextual strings the speech recognizer would receive. No real recognition runs.
@MainActor
final class MobileVocabularyUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--vocabulary-fixture", "-autoQuickSummary", "NO", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        return app
    }

    private func recognizer(_ app: XCUIApplication) -> String {
        app.staticTexts["vocabularyRecognizerTerms"].label
    }

    private func waitFor(_ app: XCUIApplication, _ predicate: @escaping (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if predicate(recognizer(app)) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return predicate(recognizer(app))
    }

    func testSuggestionAddUseByDefaultAndAddToMyTerms() {
        let app = launch()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor(app) { $0 == "recognizer: 0" }, recognizer(app))
        app.buttons["vocabularySpeak"].tap()

        let question = app.staticTexts["Sounds like a medical conversation — add the Medical vocabulary?"]
        XCTAssertTrue(question.waitForExistence(timeout: 15), "the on-device check offers Medical")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "not a medical device"))
            .firstMatch.exists)
        XCTAssertFalse(recognizer(app).contains("medical"), "a suggestion never turns anything on")
        capture(app, "Medical vocabulary suggestion")

        app.buttons["vocabularyAdd"].tap()
        XCTAssertTrue(waitFor(app) { $0.contains("· medical") }, "Add reaches the running recognizer: \(recognizer(app))")
        XCTAssertTrue(app.buttons["Stop listening"].exists, "the microphone kept running")
        XCTAssertTrue(app.staticTexts["Medical vocabulary is on for this conversation."].waitForExistence(timeout: 5))
        capture(app, "Medical vocabulary added")
        app.buttons["vocabularyUseByDefault"].tap()
        XCTAssertFalse(question.exists)

        // The latest line is the one the live transcript panel shows.
        let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Kubeflow results")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.press(forDuration: 1.2)
        let add = app.buttons["Add to My terms…"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let candidate = app.buttons["candidate-Kubeflow"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        capture(app, "Add to My terms from a transcript line")
        candidate.tap()
        app.buttons["addTermDone"].tap()
        XCTAssertTrue(waitFor(app) { $0.contains("first: Kubeflow") }, recognizer(app))
        app.buttons["Stop listening"].tap()

        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let link = app.buttons["vocabularySettings"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.switches["preset-medical"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["preset-medical"].value as? String, "1", "Use by default turned Medical on")
        XCTAssertTrue(app.staticTexts["not a medical device"].exists
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "not a medical device"))
                        .firstMatch.exists)
        for _ in 0..<8 where !app.buttons["myTerm-Kubeflow"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["myTerm-Kubeflow"].exists)
        capture(app, "Vocabularies settings")
    }

    func testChineseSpeechOffersPresetAndAppliesChineseRecognitionTerms() {
        let app = XCUIApplication()
        app.launchArguments = ["--vocabulary-fixture", "--chinese-vocabulary-fixture",
                               "-autoQuickSummary", "NO", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 10))
        app.buttons["vocabularySpeak"].tap()
        XCTAssertTrue(app.buttons["vocabularyAdd"].waitForExistence(timeout: 15))
        XCTAssertFalse(recognizer(app).contains("简体中文"), "suggestions never enable a preset")
        app.buttons["vocabularyAdd"].tap()
        XCTAssertTrue(waitFor(app) { $0.contains("简体中文") && $0.contains("first: 心房颤动") }, recognizer(app))
        XCTAssertTrue(app.buttons["Stop listening"].exists)
        capture(app, "Chinese vocabulary reaches the live recognizer")
        app.buttons["Stop listening"].tap()
    }

    func testDontSuggestAgainMutesThePreset() {
        let app = launch()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 10))
        app.buttons["vocabularySpeak"].tap()
        let mute = app.buttons["vocabularyMute"]
        XCTAssertTrue(mute.waitForExistence(timeout: 15))
        mute.tap()
        XCTAssertFalse(app.otherElements["vocabularySuggestion"].exists)
        XCTAssertEqual(recognizer(app), "recognizer: 0")
        app.buttons["Stop listening"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let link = app.buttons["vocabularySettings"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.buttons["unmute-medical"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
