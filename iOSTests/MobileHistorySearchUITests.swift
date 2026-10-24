import XCTest

/// History search with snippets and the "Ask your history" control (issue #57).
@MainActor
final class MobileHistorySearchUITests: XCTestCase {

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
