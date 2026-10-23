import XCTest

/// Issue #202: Settings → About → Acknowledgements lists every bundled package with its full license.
@MainActor
final class MobileAcknowledgementsUITests: XCTestCase {
    func testAcknowledgementsListPackagesAndOpenTheirLicenseText() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let form = app.collectionViews["aiSettingsForm"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let link = app.buttons["acknowledgements"]
        for _ in 0..<30 where !(link.exists && link.isHittable) { form.swipeUp() }
        link.tap()
        let list = app.collectionViews["acknowledgementsList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["notice-fluidaudio"].exists, "Speaker labels link FluidAudio")
        let whisper = app.buttons["notice-whisperkit"]
        for _ in 0..<10 where !(whisper.exists && whisper.isHittable) { list.swipeUp() }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Acknowledgements"; attachment.lifetime = .keepAlways; add(attachment)
        whisper.tap()
        let text = app.staticTexts["noticeText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("MIT License"), "WhisperKit's license text is shown in full")
    }
}
