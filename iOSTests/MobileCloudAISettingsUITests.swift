import XCTest

@MainActor
final class MobileCloudAISettingsUITests: XCTestCase {
    /// Issue #214: a cloud AI service is an explicit choice from the Summary provider menu, says who
    /// receives the transcript, links to the vendor's key and privacy pages, and picks no model.
    func testCloudServiceIsExplicitDisclosedAndPicksNoModel() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        app.buttons["summaryProvider"].tap()
        XCTAssertTrue(app.buttons["Anthropic Claude"].waitForExistence(timeout: 3))
        for vendor in ["OpenAI", "Google Gemini", "DeepSeek", "OpenRouter", "Groq", "Mistral", "xAI Grok"] {
            XCTAssertTrue(app.buttons[vendor].exists, vendor)
        }
        app.buttons["Anthropic Claude"].tap()
        let form = app.collectionViews["aiSettingsForm"]
        let disclosure = app.staticTexts["cloudAIDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertEqual(disclosure.label, "Sends your transcript to Anthropic")
        XCTAssertTrue(app.staticTexts["cloudAIDestination"].label.contains("api.anthropic.com"))
        let keyPage = app.buttons["cloudAIKeyPage"]
        revealSettingsControl(keyPage, in: form)
        XCTAssertTrue(keyPage.label.contains("Get a key from Anthropic"), keyPage.label)
        let refresh = app.buttons["refreshCloudAIModels"]
        revealSettingsControl(refresh, in: form)
        XCTAssertFalse(refresh.isEnabled, "Nothing is fetched before a key exists")
        let quick = app.buttons["choose-model-quick"]
        revealSettingsControl(quick, in: form)
        XCTAssertTrue(quick.label.contains("Choose model"), quick.label)
        revealSettingsControl(app.buttons["summaryProvider"], in: form, towardTop: true)
        XCTAssertTrue(app.buttons["summaryProvider"].label.contains("Anthropic Claude"), app.buttons["summaryProvider"].label)
        app.buttons["summaryProvider"].tap()
        app.buttons["Apple Intelligence · on-device"].tap()
        XCTAssertFalse(app.staticTexts["cloudAIDisclosure"].exists)
    }
}
