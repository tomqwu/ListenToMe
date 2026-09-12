import XCTest

@MainActor
final class MobileTranscriptUITests: XCTestCase {
    func testCompactTranscriptFollowsPartialAndFinalTextButRespectsReadingHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--transcript-scroll-fixture"]
        app.launch()
        let scroll = app.scrollViews["transcriptScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let transcript = app.otherElements["transcriptPanel"]
        let quick = app.otherElements["summary-panel-quick"]
        XCTAssertLessThan(transcript.frame.height, quick.frame.height * 0.7)

        expectLatestVisible(in: scroll)
        let partialID = latestText(in: scroll).identifier
        app.buttons["fixture-grow"].tap()
        XCTAssertEqual(latestText(in: scroll).identifier, partialID, "Exercise a growing partial with the same ID")
        expectLatestVisible(in: scroll)
        capture(app, "Compact transcript follows growing speech")

        scroll.swipeDown()
        scroll.swipeDown()
        let latest = app.buttons["Jump to latest transcript"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let visible = scroll.staticTexts.allElementsBoundByIndex.first {
            scroll.frame.intersection($0.frame).height > 24 && $0.identifier.hasPrefix("transcript-text-")
        }
        XCTAssertNotNil(visible)
        guard let visible else { return }
        let position = visible.frame.minY
        app.buttons["fixture-grow"].tap()
        XCTAssertEqual(visible.frame.minY, position, accuracy: 2, "Incoming speech must preserve the reading position")
        XCTAssertTrue(latest.exists)
        capture(app, "Reading history pauses auto follow")
        latest.tap()
        expectLatestVisible(in: scroll)
        XCTAssertFalse(latest.exists)
        app.buttons["fixture-finalize"].tap()
        expectLatestVisible(in: scroll)
        XCTAssertNotEqual(latestText(in: scroll).identifier, partialID)

        app.buttons["Expand transcript"].tap()
        XCTAssertTrue(app.navigationBars["Transcript"].waitForExistence(timeout: 5))
        expectLatestVisible(in: app.scrollViews["expandedTranscriptScroll"])
        capture(app, "Expanded transcript")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Notes"].isHittable)
        app.buttons["New"].tap()
        XCTAssertTrue(app.staticTexts["Start listening and your words will appear here."].exists)
        capture(app, "Compact empty transcript")
    }

    func testLargeTextUsesLatestPreviewAndExpandedHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--transcript-scroll-fixture", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let outer = app.scrollViews["dashboardScroll"]
        XCTAssertTrue(outer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["transcriptScroll"].exists, "The preview must not create nested scrolling")
        XCTAssertTrue(app.staticTexts["latestTranscriptPreview"].exists)
        app.buttons["Expand transcript"].tap()
        let reader = app.scrollViews["expandedTranscriptScroll"]
        expectLatestVisible(in: reader)
        capture(app, "Large text expanded transcript")
        app.buttons["Done"].tap()
        let quick = app.buttons["panel-model-quick"]
        for _ in 0..<8 {
            if app.windows.firstMatch.frame.contains(quick.frame) { break }
            outer.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(app.windows.firstMatch.frame.contains(quick.frame))
        capture(app, "Large text summary remains reachable")
    }

    private func latestText(in scroll: XCUIElement) -> XCUIElement {
        let texts = scroll.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcript-text-"))
        return texts.allElementsBoundByIndex.last ?? texts.firstMatch
    }

    private func expectLatestVisible(in scroll: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let text = self.latestText(in: scroll)
            return text.frame.maxY <= scroll.frame.maxY + 1 && text.frame.maxY > scroll.frame.minY + 24
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
