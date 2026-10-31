import XCTest

@MainActor
final class MobileTranscriptUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    func testCompactTranscriptFollowsPartialAndFinalTextButRespectsReadingHistory() {
        let app = XCUIApplication()
        // A preceding correction test must not add a setup banner to this geometry fixture.
        app.launchArguments = ["--transcript-scroll-fixture", "-mobileCorrectTranscript", "NO", "-mobileIdentifySpeakers", "YES"]
        app.launchPastReleaseNotes()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Speaker labels on"),
                                             object: app.staticTexts["captureStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["Start listening"].isEnabled, "Transcript geometry uses an explicit supported profile")
        XCTAssertFalse(app.staticTexts["recordingSupportReason"].exists)
        let scroll = app.scrollViews["transcriptScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let transcript = app.otherElements["transcriptPanel"]
        let quick = app.otherElements["summary-panel-quick"]
        let transcriptShare = transcript.frame.height / (transcript.frame.height + quick.frame.height)
        XCTAssertGreaterThanOrEqual(transcriptShare, 0.43, "Populated speech keeps the approved reading allocation")
        XCTAssertLessThanOrEqual(transcriptShare, 0.5, "Quick Summary retains at least half the combined panel height")

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
        let position = settledPosition(of: visible)
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
        app.launchArguments = ["--transcript-scroll-fixture", "-mobileCorrectTranscript", "NO", "-mobileIdentifySpeakers", "YES",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchPastReleaseNotes()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Speaker labels on"),
                                             object: app.staticTexts["captureStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
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

    func testLongTranscriptRemainsResponsiveAndPreservesReadingPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["--transcript-scroll-fixture", "--long-transcript-fixture", "-mobileCorrectTranscript", "NO", "-mobileIdentifySpeakers", "YES"]
        app.launchPastReleaseNotes()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Speaker labels on"),
                                             object: app.staticTexts["captureStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let scroll = app.scrollViews["transcriptScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        expectLatestVisible(in: scroll)
        scroll.swipeDown()
        XCTAssertTrue(app.buttons["Jump to latest transcript"].waitForExistence(timeout: 5))
        let visible = scroll.staticTexts.allElementsBoundByIndex.reversed().first {
            scroll.frame.intersection($0.frame).height > 24 && $0.identifier.hasPrefix("transcript-text-")
        }
        guard let visible else { XCTFail("Expected readable history"); return }
        let position = settledPosition(of: visible)
        app.buttons["fixture-grow"].tap()
        XCTAssertEqual(visible.frame.minY, position, accuracy: 2)
        app.buttons["Jump to latest transcript"].tap()
        expectLatestVisible(in: scroll)
        capture(app, "One thousand transcript segments remain readable")
    }

    private func settledPosition(of element: XCUIElement) -> CGFloat {
        var previous: CGFloat?
        var stableSamples = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = element.frame.minY
            if let previous, abs(previous - current) < 0.25 { stableSamples += 1 }
            else { stableSamples = 0 }
            previous = current
            return stableSamples >= 2
        }, object: nil)
        // Swipe completion can precede the end of scroll deceleration. Establish a stationary
        // baseline before introducing speech, without relaxing the two-point preservation check.
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 6), .completed)
        return element.frame.minY
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
