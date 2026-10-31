import XCTest

@MainActor
final class MobileOpenAISettingsUITests: XCTestCase {
    /// Issue #52: an OpenAI-compatible server is an explicit choice, a numeric plain-http address is
    /// refused with a reason, and a .local server is labelled "your server", never on-device.
    func testOpenAICompatibleServerIsExplicitAndHonestlyLabelled() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        app.buttons["summaryProvider"].tap()
        app.buttons["Custom server (OpenAI-compatible)"].tap()
        let form = app.collectionViews["aiSettingsForm"]
        XCTAssertTrue(app.staticTexts["openAIDestination"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["openAIDestination"].label.contains("Nothing is sent until you set one"))
        let field = app.textFields["openAIBaseURL"]
        revealSettingsControl(field, in: form)
        field.tap()
        field.typeText("http://192.168.1.20:1234/v1")
        app.buttons["saveOpenAIBaseURL"].tap()
        let status = app.staticTexts["ollamaStatus"]
        revealSettingsControl(status, in: form)
        XCTAssertTrue(status.label.contains("Plain http:// is only allowed"), status.label)
        app.buttons["Done"].tap()
        app.buttons["More"].tap(); app.buttons["Settings"].tap()
        revealSettingsControl(field, in: form)
        guard let draft = field.value as? String, draft.isEmpty || draft == field.placeholderValue else {
            XCTFail("Reopening Settings must discard the rejected address draft")
            return
        }
        field.tap()
        field.typeText("http://studio.local:1234")
        XCTAssertEqual(field.value as? String, "http://studio.local:1234")
        app.buttons["saveOpenAIBaseURL"].tap()
        revealSettingsControl(app.staticTexts["openAIServer"], in: form, towardTop: true)
        XCTAssertTrue(app.staticTexts["openAIServer"].label.contains("http://studio.local:1234/v1"))
        let destination = app.staticTexts["openAIDestination"]
        XCTAssertTrue(destination.label.contains("your server at studio.local:1234"), destination.label)
        XCTAssertFalse(destination.label.contains("on-device"), destination.label)
        revealSettingsControl(app.buttons["summaryProvider"], in: form, towardTop: true)
        XCTAssertTrue(app.buttons["summaryProvider"].label.contains("OpenAI-compatible · your server"),
                      app.buttons["summaryProvider"].label)
        let capacity = app.buttons["openAIContextWindow"]
        revealSettingsControl(capacity, in: form)
        capacity.tap()
        app.buttons["4K tokens"].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            capacity.label.contains("4K") || (capacity.value as? String)?.contains("4K") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 15), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Custom server context capacity"; screenshot.lifetime = .keepAlways; add(screenshot)
        capacity.tap()
        app.buttons["Unknown — server managed"].tap()
        revealSettingsControl(app.buttons["Remove server"], in: form)
        app.buttons["Remove server"].tap()
        revealSettingsControl(app.buttons["summaryProvider"], in: form, towardTop: true)
        app.buttons["summaryProvider"].tap()
        app.buttons["Ollama Cloud"].tap()
    }
}
