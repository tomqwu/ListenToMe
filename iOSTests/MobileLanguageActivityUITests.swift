import XCTest

@MainActor
final class MobileLanguageActivityUITests: XCTestCase {
    func testAudioActivitySwitchesLanguageWithoutRecognizedWords() {
        let app = XCUIApplication()
        app.launchArguments = ["--language-activity-fixture", "-autoQuickSummary", "NO",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        let notice = app.staticTexts["languageNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 20))
        XCTAssertTrue(notice.label.contains("Detected"), notice.label)
        XCTAssertEqual(app.staticTexts["activityFixtureResults"].label, "Recognized results: 0")
        XCTAssertTrue(app.buttons["undoLanguageSwitch"].isEnabled)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Audio-driven language switch without recognition results"
        image.lifetime = .keepAlways
        add(image)
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
    }
}
