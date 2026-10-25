import XCTest

@MainActor
final class MobileRetranscriptionUITests: XCTestCase {
    func testPreviewKeepOriginalAndReplace() {
        let app = XCUIApplication()
        app.launchArguments = ["--saved-audio-fixture"]
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        let entry = app.buttons["retranscribeSavedAudio"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["startRetranscription"].waitForExistence(timeout: 5))
        app.buttons["startRetranscription"].tap()
        XCTAssertTrue(app.buttons["replaceTranscript"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You: Re-transcribed saved audio example."].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Review saved-audio re-transcription before replacing"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["keepOriginalTranscript"].tap()
        XCTAssertTrue(app.staticTexts["Line 3 of the recorded conversation."].waitForExistence(timeout: 5))
        app.buttons["More"].tap()
        app.buttons["retranscribeSavedAudio"].tap()
        app.buttons["startRetranscription"].tap()
        XCTAssertTrue(app.buttons["replaceTranscript"].waitForExistence(timeout: 10))
        app.buttons["replaceTranscript"].tap()
        XCTAssertTrue(app.staticTexts["Re-transcribed saved audio example."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Line 3 of the recorded conversation."].exists)
    }
}
