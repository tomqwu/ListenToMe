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

    func testRecordingLandscapeKeepsDuoPanelsNoticeAndExplicitStopUsable() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--recording-continuity-fixture", "-autoQuickSummary", "NO",
                               "-mobileIdentifySpeakers", "NO"]
        app.launchPastReleaseNotes()
        let start = app.buttons["Start listening"]
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        let stop = app.buttons["Stop listening"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        let notice = app.staticTexts["backgroundRecordingNotice"]
        XCTAssertTrue(notice.isHittable)
        capture(app, "Portrait recording with screen lock disclosure")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        XCTAssertTrue(app.otherElements["twoPaneMeetingWorkspace"].waitForExistence(timeout: 3),
                      "A recording phone must retain Duo rather than falling back to stacked panels")
        let transcript = app.otherElements["transcriptPanel"].frame
        let quick = app.otherElements["summary-panel-quick"].frame
        XCTAssertLessThanOrEqual(transcript.maxX, quick.minX + 1)
        XCTAssertGreaterThan(transcript.width, 100); XCTAssertGreaterThan(quick.width, 100)
        XCTAssertTrue(app.buttons["Expand transcript"].isHittable)
        XCTAssertTrue(app.buttons["panel-model-quick"].isHittable)
        XCTAssertTrue(app.staticTexts["output-quick"].isHittable)
        XCTAssertTrue(stop.isHittable)
        XCTAssertTrue(notice.isHittable)
        XCTAssertTrue(notice.label.contains("Optional AI updates resume when you return"))
        XCTAssertTrue(app.staticTexts["continuityFixtureProbe"].label.contains("starts=1; stops=0"))
        capture(app, "Landscape recording Duo panels and accessible screen lock disclosure")
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5)); XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(app.staticTexts["continuityFixtureProbe"].label.contains("starts=1; stops=1"))
        capture(app, "Landscape explicit Stop remains usable")
        app.terminate()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
