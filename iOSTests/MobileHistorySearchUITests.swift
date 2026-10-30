import XCTest

/// History search with snippets and the "Ask your history" control (issue #57).
@MainActor
final class MobileHistorySearchUITests: XCTestCase {

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
