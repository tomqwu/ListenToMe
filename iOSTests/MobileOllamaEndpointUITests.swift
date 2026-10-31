import XCTest

@MainActor
final class MobileOllamaEndpointUITests: XCTestCase {
    func testRejectedHTTPAndOmittedURLPartsAreExplained() {
        let app = XCUIApplication()
        app.launchArguments = ["-mobileAIProvider", "ollama", "-mobileOllamaBaseURL", "https://studio.local:11434"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["More"].tap(); app.buttons["Settings"].tap()
        let form = app.collectionViews["aiSettingsForm"]
        let field = app.textFields["ollamaBaseURL"]
        let status = app.staticTexts["ollamaStatus"]
        revealSettingsControl(field, in: form)
        field.tap(); field.typeText("http://100.64.0.1:11434\n")
        app.buttons["Save server URL"].tap()
        revealSettingsControl(status, in: form)
        XCTAssertTrue(status.label.contains("Use https://"))
        XCTAssertTrue(status.label.contains("previous server is kept"))
        capture(app, "HTTP address rejected with recovery instructions")
        revealSettingsControl(field, in: form, towardTop: true)
        field.tap()
        // Select the entire address without depending on the transient editing menu or caret position.
        field.typeKey("a", modifierFlags: .command)
        field.typeText("https://studio.local:11434/ollama?token=test-value")
        XCTAssertEqual(field.value as? String, "https://studio.local:11434/ollama?token=test-value")
        field.typeText("\n")
        app.buttons["Save server URL"].tap()
        revealSettingsControl(status, in: form)
        XCTAssertTrue(status.label.contains("Only the scheme, host and port"))
        XCTAssertFalse(status.label.contains("test-value"))
        capture(app, "Omitted URL parts explained without query values")
        app.buttons["Done"].tap()
        app.buttons["More"].tap(); app.buttons["Settings"].tap()
        let restore = app.buttons["Use Ollama Cloud instead"]
        revealSettingsControl(restore, in: form)
        restore.tap()
        app.buttons["Done"].tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
