import XCTest

@MainActor
final class MobileReviewLimitUITests: XCTestCase {
    func testOversizedReviewExplainsTheLimitAndShorterInputRecovers() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "--review-limit-fixture",
                               "-autoQuickSummary", "YES", "-mobileAIProvider", "apple"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 5))
        app.buttons["oversizedReview"].tap()
        app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        let status = app.staticTexts["autoReviewStatus-summary"]
        let limit = NSPredicate(format: "label CONTAINS %@", "Request exceeds the review limit")
        expectation(for: limit, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(status.isHittable)
        capture(app, "Automatic review limit explains what to shorten")
        app.buttons["shortenReview"].tap()
        let output = app.staticTexts["output-summary"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Thursday"), evaluatedWith: output)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(status.label.contains("exceeds the review limit"))
        capture(app, "Shorter automatic review recovers")
        app.buttons["Stop listening"].tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
