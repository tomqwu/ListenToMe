import XCTest

@MainActor
final class MobileWatchSpeakerUITests: XCTestCase {
    func testWatchSpeakerLabelsRenderInTranscriptAndNotes() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["Expand transcript"].tap()
        XCTAssertTrue(app.staticTexts["Speaker 1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Speaker 2"].firstMatch.exists)
        XCTAssertTrue(app.otherElements["savedAudioPlayer"].waitForExistence(timeout: 5))
        app.buttons["Play from 0:11"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["shareSavedAudio"].exists)
        capture("Watch recording with identified speakers and saved audio")
        app.navigationBars["Transcript"].buttons["Done"].tap()
        app.buttons["Notes"].tap()
        let field = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'speakerName-watch:'")).firstMatch
        let form = app.collectionViews.firstMatch
        for _ in 0..<10 where !field.isHittable { form.swipeUp() }
        XCTAssertTrue(field.isHittable)
        capture("Watch speaker names in Notes")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
