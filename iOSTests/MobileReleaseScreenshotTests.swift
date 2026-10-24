import XCTest

/// Native-resolution release assets use only synthetic content in the real app views.
/// Run this class on every release device in docs/IOS-RELEASING.md, then export attachments.
@MainActor
final class MobileReleaseScreenshotTests: XCTestCase {
    func testCaptureReleaseScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchPastReleaseNotes()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5))
        app.scrollViews["transcriptScroll"].swipeDown()
        capture("01 Live portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["Notes"].isHittable)
        app.scrollViews["transcriptScroll"].swipeDown()
        capture("02 Live landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Notes"].tap()
        let form = app.collectionViews.firstMatch
        let mode = app.segmentedControls["conversationPromptMode"]
        reveal(mode, in: form)
        XCTAssertTrue(mode.isHittable)
        mode.buttons["Summary instructions"].tap()
        app.buttons["conversationPromptPresets"].tap()
        app.buttons["Software & Cloud"].tap()
        let save = app.buttons["saveConversationInstructions"]
        reveal(save, in: form)
        XCTAssertTrue(save.isHittable)
        save.tap()
        capture("03 Conversation prompt")
        app.buttons["Done"].tap()
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        }
        XCTAssertTrue(app.buttons["panel-model-summary"].waitForExistence(timeout: 5))
        capture("04 Summary portrait")
    }

    private func reveal(_ element: XCUIElement, in form: XCUIElement) {
        // Scroll the form's edge, avoiding the nested Notes and Prompt text editors on iPad.
        for _ in 0..<12 where !element.isHittable {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.65)))
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
