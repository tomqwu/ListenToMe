import XCTest

@MainActor
final class MobileSpeakerControlsUITests: XCTestCase {
    func testSpeakerOptOutIsReachableWhileListeningAndOptInWaitsForStop() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "NO",
                               "-mobileAIProvider", "apple", "-mobileIdentifySpeakers", "YES"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 5))
        openSettings(app)
        let row = app.switches["identifySpeakersToggle"].firstMatch
        let toggle = row.switches.firstMatch
        revealSettingsControl(row, in: app.collectionViews["aiSettingsForm"])
        XCTAssertTrue(toggle.exists, "Operate the native switch, rather than tapping its containing label row")
        XCTAssertTrue(toggle.isEnabled, "The user must be able to withdraw speaker consent while recording")
        guard toggle.isEnabled else { return }
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(toggle.isEnabled, "A new speaker run starts with the next recording, after Stop")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Speaker opt-out while recording"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].isEnabled, "Optional speaker consent cannot stop transcription")
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        openSettings(app)
        revealSettingsControl(row, in: app.collectionViews["aiSettingsForm"])
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String, "0", "The off choice must survive Stop and reopening Settings")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
