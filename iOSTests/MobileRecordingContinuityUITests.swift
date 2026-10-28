import XCTest

@MainActor
final class MobileRecordingContinuityUITests: XCTestCase {
    func testHomeReturnKeepsOneVisibleRecordingAndExplicitStopEndsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--recording-continuity-fixture", "-autoQuickSummary", "NO",
                               "-mobileIdentifySpeakers", "NO"]
        app.launchPastReleaseNotes()
        let start = app.buttons["Start listening"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        let stop = app.buttons["Stop listening"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let probe = app.staticTexts["continuityFixtureProbe"]
        XCTAssertTrue(probe.label.contains("starts=1; stops=0; backgrounds=0"))
        capture(app, "Recording before actual simulator background")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["captureStatus"].label.contains("Listening"))
        XCTAssertTrue(probe.label.contains("starts=1; stops=0; backgrounds=1"), probe.label)
        XCTAssertTrue(app.staticTexts["backgroundRecordingNotice"].exists,
                      "The recording screen must explain continued capture and paused optional AI")
        capture(app, "Same recording after actual simulator background and return")
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5)); XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(probe.label.contains("starts=1; stops=1; backgrounds=1"), probe.label)
        capture(app, "Explicit Stop after simulator background")
        app.terminate()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
