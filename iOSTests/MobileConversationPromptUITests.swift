import XCTest

@MainActor
final class MobileConversationPromptUITests: XCTestCase {
    func testPromptPresetsSaveAndReopenNotes() {
        let app = XCUIApplication()
        app.launchArguments = ["--transcript-scroll-fixture", "--two-pane-layout-fixture"]
        app.launchPastReleaseNotes()
        app.buttons["Notes"].tap()
        let form = app.collectionViews.firstMatch
        let mode = app.segmentedControls["conversationPromptMode"]
        for _ in 0..<5 where !mode.isHittable { form.swipeUp() }
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["Summary instructions"].tap()
        app.buttons["conversationPromptPresets"].tap()
        app.buttons["Software & Cloud"].tap()
        let save = app.buttons["saveConversationInstructions"]
        for _ in 0..<5 where !save.isHittable { form.swipeUp() }
        save.tap()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Conversation summary instructions"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Done"].tap()
        app.buttons["Notes"].tap()
        for _ in 0..<5 where !mode.isHittable { form.swipeUp() }
        mode.buttons["Summary instructions"].tap()
        let draft = app.textFields["conversationPromptDraft"]
        let text = app.textViews["conversationPromptDraft"]
        let value = (draft.exists ? draft.value : text.value) as? String ?? ""
        XCTAssertTrue(value.contains("software"), value)
        mode.buttons["Ask once"].tap()
        XCTAssertFalse(app.buttons["askConversationPrompt"].isEnabled, "An empty Ask never sends a request")
    }
}
