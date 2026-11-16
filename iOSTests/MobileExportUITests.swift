import XCTest

/// Issue #130: More → Export as offers each file format, and the share sheet receives a file named
/// after the conversation. A notes-only conversation has no timestamps, so no subtitle formats.
@MainActor
final class MobileExportUITests: XCTestCase {
    func testExportAsOffersFormatsAndSharesANamedFile() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        app.textViews["Conversation notes"].tap()
        app.textViews["Conversation notes"].typeText("Export check")
        app.buttons["Done"].tap()

        app.buttons["More"].tap()
        let exportAs = app.buttons["exportAs"]
        XCTAssertTrue(exportAs.waitForExistence(timeout: 5), app.debugDescription)
        exportAs.tap()
        for format in ["Markdown", "Plain text", "JSON"] {
            XCTAssertTrue(app.buttons[format].waitForExistence(timeout: 5), "\(format): \(app.debugDescription)")
        }
        XCTAssertFalse(app.buttons["Subtitles (SRT)"].exists, "no timestamps, so no subtitles")
        XCTAssertFalse(app.buttons["Subtitles (WebVTT)"].exists)

        app.buttons["JSON"].tap()
        // The share sheet's header shows the file's name and, below it, its type: a real JSON file.
        let named = app.descendants(matching: .any)["LP.CaptionBar.TopCaption"]
        XCTAssertTrue(named.waitForExistence(timeout: 15), "share sheet shows the file name: \(app.debugDescription)")
        XCTAssertTrue(named.label.hasPrefix("Conversation "), named.label)
        let type = app.descendants(matching: .any)["LP.CaptionBar.BottomCaption"]
        XCTAssertTrue(type.label.hasPrefix("JSON"), "share sheet receives a JSON file: \(type.label)")
    }
}
