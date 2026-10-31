import XCTest
import UIKit

/// Native-resolution release assets use only synthetic content in the real app views.
/// Run this class on every release device in docs/IOS-RELEASING.md, then export attachments.
@MainActor
final class MobileReleaseScreenshotTests: XCTestCase {
    func testCaptureCleanDuoPreview() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Duo preview is an iPhone capture; iPad uses the separate wide-workspace release images")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "--release-duo-fixture", "-autoQuickSummary", "NO",
                               "-mobileAIProvider", "apple", "-mobileCorrectTranscript", "NO",
                               "-mobileIdentifySpeakers", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        XCUIDevice.shared.orientation = .portrait
        defer {
            capture("Duo preview transcript and Quick visibility")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        app.launchPastReleaseNotes()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 10))
        let portraitWindow = app.windows.firstMatch.frame
        XCTAssertGreaterThan(portraitWindow.height, portraitWindow.width)
        let portraitTranscript = app.otherElements["transcriptPanel"]
        let portraitLines = portraitTranscript.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcript-text-"))
        XCTAssertEqual(portraitLines.count, 2)
        let portraitWording = portraitLines.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(portraitWording.contains("Alex") && portraitWording.contains("Thursday"))
        let portraitViewport = app.scrollViews["transcriptScroll"].frame.intersection(portraitWindow)
        for line in portraitLines.allElementsBoundByIndex { assertWholePreviewText(line, in: portraitViewport) }
        let portraitAnswer = app.staticTexts["output-quick"]
        XCTAssertTrue(portraitAnswer.waitForExistence(timeout: 5))
        let portraitQuick = app.otherElements["summary-panel-quick"].scrollViews.firstMatch
        let answerViewport = portraitQuick.frame.intersection(portraitWindow)
        if !answerViewport.contains(portraitAnswer.frame) {
            // Status precedes the answer in this panel's normal scroll view.
            let overflow = portraitAnswer.frame.maxY - answerViewport.maxY + 8
            let distance = min(max(44, overflow), answerViewport.height / 3)
            let start = portraitQuick.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.8))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)))
        }
        XCTAssertTrue(portraitAnswer.label.contains("Alex") && portraitAnswer.label.contains("Thursday"))
        let settledWindow = app.windows.firstMatch.frame
        assertWholePreviewText(portraitAnswer, in: portraitQuick.frame.intersection(settledWindow))
        let settledTranscript = app.scrollViews["transcriptScroll"].frame.intersection(settledWindow)
        for line in portraitLines.allElementsBoundByIndex { assertWholePreviewText(line, in: settledTranscript) }
        capture("Clean portrait transcript and Quick visibility")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["twoPaneMeetingWorkspace"].waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Speaker labels on"),
                                             object: app.staticTexts["captureStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height)
        let transcript = app.otherElements["transcriptPanel"]
        let quick = app.otherElements["summary-panel-quick"]
        XCTAssertGreaterThanOrEqual(quick.frame.minX, transcript.frame.maxX)
        XCTAssertEqual(quick.frame.minY, transcript.frame.minY, accuracy: 2)
        let lines = transcript.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcript-text-"))
        XCTAssertEqual(lines.count, 2, "This preview has exactly two authored final lines, not a long history")
        let wording = lines.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(wording.contains("Alex") && wording.contains("Thursday"))
        let transcriptViewport = app.scrollViews["transcriptScroll"].frame.intersection(window)
        for line in lines.allElementsBoundByIndex { assertWholePreviewText(line, in: transcriptViewport) }
        let answer = app.staticTexts["output-quick"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertTrue(answer.label.contains("Alex") && answer.label.contains("Thursday"),
                      "The authored answer must be present, rather than an empty-output placeholder")
        assertWholePreviewText(answer, in: quick.scrollViews.firstMatch.frame.intersection(window))
        XCTAssertTrue(app.buttons["Start listening"].isEnabled)
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        XCTAssertTrue(app.buttons["Notes"].isHittable)
        let update = app.buttons["generate-quick"]
        XCTAssertTrue(update.isHittable)
        XCTAssertEqual(update.label, "Update Quick Summary")
        XCTAssertGreaterThanOrEqual(update.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["Start listening"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["Notes"].frame.height, 44)
        XCTAssertTrue(window.contains(app.buttons["Start listening"].frame))
        XCTAssertTrue(window.contains(app.buttons["Notes"].frame))
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        XCTAssertFalse(app.buttons["Jump to latest transcript"].exists)
        XCTAssertFalse(app.buttons["retrySpeakers"].exists)
        XCTAssertFalse(app.staticTexts["recordingSupportReason"].exists)
        XCTAssertFalse(app.buttons["fixture-grow"].exists)
        XCTAssertFalse(app.buttons["releaseHeldTranslation"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func assertWholePreviewText(_ element: XCUIElement, in viewport: CGRect,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertFalse(element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
        XCTAssertFalse(element.frame.isEmpty, file: file, line: line)
        let detail = "Preview text \(element.frame) must fit its viewport \(viewport): \(element.label)"
        XCTAssertTrue(viewport.contains(element.frame), detail, file: file, line: line)
    }

    func testCaptureReleaseScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple",
                               "-mobileCorrectTranscript", "NO"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchPastReleaseNotes()
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Correction paused")).firstMatch.exists,
                       "Release captures must not inherit correction settings from another UI journey")
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
        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        capture("05 Conversation history")
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("06 Settings")
    }

    private func reveal(_ element: XCUIElement, in form: XCUIElement) {
        // Scroll the form's edge, avoiding the nested Notes and Prompt text editors on iPad.
        for _ in 0..<12 where !element.isHittable {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.85))
                .press(forDuration: 0.05,
                       thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.65)))
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
