import XCTest

@MainActor
final class MobileReleaseNotesUITests: XCTestCase {
    func testUpdateShowsVersionOnceAndChangelogCanBeReopened() {
        let app = XCUIApplication()
        app.useModelFixtures()
        app.launchArguments = ["-lastAcknowledgedReleaseBuild", "1.11.0-19o2wbf6iijj1"]
        app.launch()
        XCTAssertTrue(app.buttons["releaseNotesContinue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["releaseVersion"].label, "Version 1.12.0 · Build 29")
        XCTAssertTrue(app.staticTexts["Names and languages, automatically"].exists)
        capture(app, "What’s New on update")
        app.buttons["releaseNotesContinue"].tap()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["releaseNotesContinue"].exists, "Acknowledged updates must not interrupt each launch")
        app.buttons["More"].tap()
        app.buttons["What’s New"].tap()
        XCTAssertTrue(app.staticTexts["releaseVersion"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Know what changed"].exists)
        app.buttons["releaseNotesContinue"].tap()
    }

    func testLargeTextKeepsContinueReachableAndHistoryScrollable() {
        let app = XCUIApplication()
        app.useModelFixtures()
        app.launchArguments = ["-lastAcknowledgedReleaseBuild", "older",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let button = app.buttons["releaseNotesContinue"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        let scroll = app.scrollViews["releaseNotesScroll"]
        for _ in 0..<40 where !app.staticTexts["Automatic reviews"].isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts["Automatic reviews"].isHittable)
        capture(app, "Large text release history with reachable Continue")
        button.tap()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
