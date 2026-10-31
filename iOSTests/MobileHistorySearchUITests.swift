import XCTest
import UIKit

/// History search with snippets and the "Ask your history" control (issue #57).
@MainActor
final class MobileHistorySearchUITests: XCTestCase {

    func testLandscapeHistoryKeepsRefreshAskAndResultReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.launchPastReleaseNotes()
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        let workspace = UIDevice.current.userInterfaceIdiom == .phone
            ? "twoPaneMeetingWorkspace" : "wideMeetingWorkspace"
        XCTAssertTrue(app.otherElements[workspace].waitForExistence(timeout: 5))
        app.buttons["History"].tap()
        let history = app.collectionViews.containing(.button, identifier: "history-refresh").firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 2) {
            history.swipeDown() // Reveal the standard collapsed search drawer on iPad.
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("prototype")
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "review the prototype")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        field.typeText("\n")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                    object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed)
        let refresh = app.buttons["history-refresh"], ask = app.buttons["history-ask"]
        let disclosure = app.staticTexts["history-ask-disclosure"]
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-record-")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); XCTAssertTrue(record.label.contains("Product planning"))
        let viewport = history.frame.intersection(app.windows.firstMatch.frame)
        XCTAssertFalse(viewport.isEmpty)
        for control in [refresh, ask] {
            XCTAssertTrue(control.exists); XCTAssertTrue(control.isHittable)
            XCTAssertFalse(control.frame.isEmpty); XCTAssertTrue(viewport.contains(control.frame))
        }
        XCTAssertTrue(disclosure.exists); XCTAssertFalse(disclosure.frame.isEmpty)
        XCTAssertTrue(viewport.contains(disclosure.frame))
        XCTAssertFalse(disclosure.frame.intersects(field.frame))
        XCTAssertLessThanOrEqual(refresh.frame.maxY, ask.frame.minY)
        XCTAssertLessThanOrEqual(ask.frame.maxY, disclosure.frame.minY)
        refresh.tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 10), .completed)
        XCTAssertEqual(field.value as? String, "prototype")
        XCTAssertTrue(result.exists); XCTAssertTrue(ask.isHittable)
        captureHistory("Queried History controls - QA")

        if record.frame.intersects(field.frame) {
            let overlap = record.frame.maxY - field.frame.minY + 8
            // A small overlap still needs a meaningful scroll gesture.
            let distance = min(max(44, overlap), viewport.height / 3)
            let start = history.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)))
        }
        XCTAssertTrue(record.isHittable); XCTAssertFalse(record.frame.isEmpty)
        XCTAssertTrue(viewport.contains(record.frame))
        XCTAssertFalse(record.frame.intersects(field.frame),
                       "Search must not cover the selected result: record=\(record.frame), search=\(field.frame)")
        XCTAssertEqual(field.value as? String, "prototype")
        captureHistory("Queried History result - QA")
        record.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: history)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        let title = app.textFields["conversationTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.value as? String, "Product planning")
        let transcript = app.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcript-text-")).firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertTrue(transcript.label.contains("Let's keep the first release"))

        app.buttons["History"].tap()
        XCTAssertTrue(refresh.waitForExistence(timeout: 5)); XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertFalse(ask.exists); XCTAssertTrue(app.buttons["deleteAllConversations"].exists)
        let reopenedViewport = history.frame.intersection(app.windows.firstMatch.frame)
        for control in [refresh, record] {
            XCTAssertTrue(control.isHittable); XCTAssertFalse(control.frame.isEmpty)
            XCTAssertTrue(reopenedViewport.contains(control.frame))
            if field.exists { XCTAssertFalse(control.frame.intersects(field.frame)) }
        }
        XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertFalse(app.keyboards.firstMatch.exists)
        captureHistory("Landscape History refresh and result (unqueried)")
    }

    private func captureHistory(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testExplicitRefreshKeepsLiteralHistoryResultAndReturnsToIdle() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes(); app.buttons["History"].tap()
        let refresh = app.buttons["history-refresh"]
        guard refresh.waitForExistence(timeout: 5) else { XCTFail("History must expose explicit Refresh search"); return }
        XCTAssertTrue(refresh.isHittable); refresh.tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        let field = app.searchFields.firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("prototype")
        let result = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "review the prototype")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        field.typeText("\n")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                    object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed,
                       "The native History preview must omit the software keyboard")
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-record-")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); XCTAssertTrue(record.label.contains("Product planning"))
        XCTAssertTrue(refresh.isHittable); XCTAssertTrue(record.isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "History explicit local refresh"
        shot.lifetime = .keepAlways; add(shot)
    }

    func testNoResultsGuidanceLeavesExplicitRefreshReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes(); app.buttons["History"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("qzxvUnmatchedHistoryRefresh")
        let empty = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "No Results")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "The unmatched query must reach actual no-results guidance")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "History no-results before Refresh"; before.lifetime = .keepAlways; add(before)
        let ask = app.buttons["history-ask"]
        let disclosure = app.staticTexts["history-ask-disclosure"]
        XCTAssertTrue(ask.exists); XCTAssertTrue(disclosure.exists)
        XCTAssertGreaterThanOrEqual(empty.frame.minY, disclosure.frame.maxY,
                                   "No-results guidance must follow Ask and its disclosure without overlapping them")
        XCTAssertFalse(empty.frame.intersects(ask.frame), "No-results guidance must not cover the Ask action")
        let refresh = app.buttons["history-refresh"]
        XCTAssertTrue(refresh.exists)
        XCTAssertTrue(refresh.isHittable, "No-results guidance must leave the actual Refresh action reachable")
        refresh.tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 10), .completed)
        XCTAssertEqual(field.value as? String, "qzxvUnmatchedHistoryRefresh")
        XCTAssertTrue(empty.exists, "Refresh must preserve the unmatched query rather than dismissing its guidance")
        XCTAssertTrue(refresh.isHittable); XCTAssertFalse(app.alerts.firstMatch.exists)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "History no-results after Refresh"; after.lifetime = .keepAlways; add(after)
    }

    func testEmptyHistoryKeepsExplicitRefreshReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes(); app.buttons["History"].tap()
        let delete = app.buttons["deleteAllConversations"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        app.alerts.buttons["Delete all"].firstMatch.tap() // Only the fixture's isolated temporary archive.
        let empty = app.staticTexts["No saved conversations"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        let refresh = app.buttons["history-refresh"]
        XCTAssertTrue(refresh.isHittable); refresh.tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 10), .completed)
        XCTAssertTrue(empty.exists); XCTAssertTrue(refresh.isHittable)
        XCTAssertFalse(app.buttons["history-ask"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Empty History keeps Refresh reachable"; shot.lifetime = .keepAlways; add(shot)
    }

    func testSearchShowsASnippetAndSaysWhereAQuestionWouldGo() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        app.buttons["History"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("prototype")
        XCTAssertTrue(app.buttons["history-ask"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["history-ask-disclosure"].exists)
        let snippet = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "review the prototype")).firstMatch
        XCTAssertTrue(snippet.waitForExistence(timeout: 10), "The matching excerpt is shown under the result")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "History search with snippet and Ask"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
