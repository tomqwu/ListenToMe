import XCTest

@MainActor
final class MobileMarkdownUITests: XCTestCase {
    func testSavedSummariesRenderOnDashboardAndFullSummary() throws {
        let app = XCUIApplication()
        app.launch()
        guard app.textFields["conversationTitle"].value as? String == "Markdown rendering fixture" else {
            throw XCTSkip("Requires the locally staged Markdown conversation fixture.")
        }
        for mode in ["quick", "deep"] {
            app.segmentedControls["workspaceTabs"].buttons[mode == "quick" ? "Live" : "Deep"].tap()
            let output = app.staticTexts["output-\(mode)"]
            XCTAssertTrue(output.waitForExistence(timeout: 5))
            XCTAssertTrue(output.label.contains("Decisions"))
            XCTAssertTrue(output.label.contains("Alex"))
            XCTAssertFalse(output.label.contains("###"))
            XCTAssertFalse(output.label.contains("**"))
        }
        capture(app, name: "Formatted Quick and Deep summaries")
        app.buttons["More"].tap()
        app.buttons["Full summary"].tap()
        let output = app.staticTexts["savedSummary"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(output.label.contains("Decisions"))
        XCTAssertFalse(output.label.contains("###"))
        XCTAssertFalse(output.label.contains("**"))
        capture(app, name: "Formatted full summary")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
