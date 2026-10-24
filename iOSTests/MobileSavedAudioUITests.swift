import XCTest

/// Settings → Save audio recordings (issue #55): off by default, explains that audio stays on the device
/// and what it costs, and offers automatic deletion once on. Nothing is recorded in this test.
@MainActor
final class MobileSavedAudioUITests: XCTestCase {
    func testSaveAudioRecordingsIsOffByDefaultAndExplainsItself() {
        let app = XCUIApplication()
        app.launchArguments = ["-saveRawAudio", "NO", "-savedAudioRetentionDays", "0"]
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let form = app.collectionViews["aiSettingsForm"]
        let toggle = app.switches["saveAudioToggle"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        revealSettingsControl(toggle, in: form)
        XCTAssertEqual(toggle.value as? String, "0", "Saving audio is opt-in")
        let retention = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Keep audio'")).firstMatch
        XCTAssertFalse(retention.exists)

        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(retention.waitForExistence(timeout: 5), "Automatic deletion is offered once it is on")
        let explanation = app.staticTexts["savedAudioExplanation"]
        revealSettingsControl(explanation, in: form)
        XCTAssertTrue((explanation.label as NSString).contains("never uploaded"), explanation.label)
        XCTAssertTrue((explanation.label as NSString).contains("per hour"), explanation.label)
        XCTAssertTrue(app.buttons["deleteAllSavedAudio"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Save audio recordings settings"; screenshot.lifetime = .keepAlways; add(screenshot)
        revealSettingsControl(toggle, in: form)
        toggle.switches.firstMatch.tap()   // leave the simulator's setting off
    }

    /// The fixture's audio is a synthetic tone written by the real writer; the microphone is never used.
    func testSavedAudioPlaysFromATappedLineAndCanBeShared() {
        let app = XCUIApplication()
        app.launchArguments = ["--saved-audio-fixture", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        let open = app.buttons["playSavedAudio"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "A conversation with saved audio offers Play recording")
        open.tap()
        let player = app.otherElements["savedAudioPlayer"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shareSavedAudio"].exists, "The audio can be exported from the share sheet")
        let line = app.buttons["Play from 0:03"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Lines with trustworthy times can seek")
        line.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "Tapping a line plays from its time")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved audio player"; screenshot.lifetime = .keepAlways; add(screenshot)
        pause.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }
}
