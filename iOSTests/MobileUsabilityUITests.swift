import XCTest

@MainActor
final class MobileUsabilityUITests: XCTestCase {
    func testUnavailableAutoExplainsManualUpdatesAndCanBeTurnedOffBeforeListening() {
        let app = XCUIApplication()
        app.launchArguments = ["-mobileAIProvider", "apple", "-autoQuickSummary", "YES",
                               "-mobileCorrectTranscript", "NO", "-mobileIdentifySpeakers", "NO"]
        app.launchPastReleaseNotes()
        let auto = app.switches["Auto summaries"].switches.firstMatch
        XCTAssertTrue(auto.waitForExistence(timeout: 10))
        XCTAssertTrue(auto.isEnabled, "A saved enabled preference can still be turned off")
        let status = app.staticTexts["autoQuickStatus"]
        XCTAssertTrue(status.label.contains("manual summaries"), status.label)
        auto.tap()
        XCTAssertEqual(auto.value as? String, "0")
        XCTAssertFalse(auto.isEnabled, "Unavailable Auto must not invite a start")
        XCTAssertTrue(status.label.contains("manual summaries"), status.label)
        app.buttons["More"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["summaryProvider"].label.contains("Apple Intelligence"))
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "Auto availability before listening")
    }

    func testPopulatedTranscriptGetsReadingSpaceAndLabeledUpdateAndCorrectionAccess() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-mobileAIProvider", "apple",
                               "-autoQuickSummary", "NO", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        let transcript = app.otherElements["transcriptPanel"]
        let quick = app.otherElements["summary-panel-quick"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(transcript.frame.height / (transcript.frame.height + quick.frame.height), 0.43)
        XCTAssertFalse(app.buttons["speechCorrectionSettings"].exists, "Optional setup must not displace speech")
        let update = app.buttons["generate-quick"]
        XCTAssertTrue(update.staticTexts["Update"].exists, "Show an action word, not just a circular arrow")
        XCTAssertEqual(update.label, "Update Quick Summary", "VoiceOver and Voice Control must match the visible action")
        XCTAssertGreaterThanOrEqual(update.frame.height, 44)
        XCTAssertTrue(app.buttons["Expand transcript"].isHittable)
        capture(app, "Transcript-first populated portrait")
        app.buttons["transcriptOptions"].tap()
        app.buttons["Speech correction settings"].tap()
        XCTAssertTrue(app.navigationBars["AI settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(transcript.exists)
    }

    func testConversationToolsAreNamedAndGroupedWithoutLosingNotes() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO"]
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        let tools = app.buttons["Notes, prompts & files"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ask AI"].exists)
        XCTAssertTrue(app.textViews["Conversation notes"].exists)
        capture(app, "Named conversation tools")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Notes"].isHittable)
        app.buttons["More"].tap(); app.buttons["Full summary"].tap()
        let update = app.buttons["full-generate-summary"]
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        XCTAssertEqual(update.label, "Update Summary")
        capture(app, "Named full summary reader action")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
    }

    func testEmptySummaryExplainsDisabledActionAndSupportsRecheck() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["New"].tap()
        app.buttons["More"].tap()
        app.buttons["Full summary"].tap()
        let reason = app.staticTexts["summaryBlockReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.contains("Add notes"))
        XCTAssertTrue(app.buttons["full-generate-summary"].exists, "The actual full-summary action must be present")
        XCTAssertFalse(app.buttons["full-generate-summary"].isEnabled)
        app.buttons["Check again"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["sessionMessage"].label.contains("Add notes"))
    }


    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
