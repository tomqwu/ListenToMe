import XCTest

@MainActor
final class WatchCapabilityUITests: XCTestCase {
    func testSimulatorPreviewShowsRecordingAndStopWithoutMicrophone() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-design-fixture", "-watchRecordingConsentShownV2", "NO"]
        app.launch()
        // Fail before touching Record if this explicit, microphone-free fixture is unavailable.
        let fixture = app.descendants(matching: .any)["watchPreviewFixture"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else { return XCTFail("Explicit simulator preview is unavailable") }
        let record = app.buttons["Record"]
        XCTAssertTrue(record.isEnabled)
        capture("Watch ready home")
        record.tap()
        // watchOS presents SwiftUI alerts as an action table rather than an AX Alert.
        let title = app.staticTexts["Before you record"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        capture("Watch recording consent")
        let consent = app.tables.firstMatch
        let confirm = consent.buttons["Record"]
        for _ in 0..<6 where !confirm.isHittable { consent.swipeUp() }
        XCTAssertTrue(confirm.isHittable, "Consent must remain readable with its action reachable")
        confirm.tap()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Recording")).firstMatch.exists)
        capture("Watch recording and Stop")
        let elapsed = app.staticTexts["watchRecordingElapsed"]
        XCTAssertTrue(elapsed.exists)
        let close = app.buttons["close-sheet"].firstMatch
        XCTAssertTrue(close.exists, "Inspect and exercise the actual system close button")
        if close.exists { close.tap() }
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(stop.isHittable, "Closing the presentation must not hide Stop during capture")
        let afterClose = elapsed.label
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label != %@", afterClose),
                                                  object: elapsed)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 3), .completed, "Recording time must keep advancing")
        // Attempting to dismiss an active presentation must not act as Stop.
        app.swipeDown()
        XCTAssertTrue(stop.exists)
        capture("Watch recording survives dismissal gesture")
        // An established recording keeps running when the app leaves the foreground.
        XCUIApplication(bundleIdentifier: "com.apple.NanoSettings").launch()
        app.activate()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        capture("Watch recording restored after background")
        stop.tap()
        XCTAssertTrue(app.buttons["Record"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Stop"].exists)
    }

    func testPendingStartDoesNotStartLaterAfterBackground() async throws {
        try await checkPendingPreview(interrupted: false)
    }

    func testPendingContinueDoesNotResumeLaterAfterBackground() async throws {
        try await checkPendingPreview(interrupted: true)
    }

    func testPendingContinueDismissalCannotResumeLater() async throws {
        try await checkPendingPreview(interrupted: true, dismiss: true)
    }

    private func checkPendingPreview(interrupted: Bool, dismiss: Bool = false) async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-design-fixture", "--watch-preview-delay-permission",
                               "-watchRecordingConsentShownV2", "YES"]
        if interrupted { app.launchArguments.append("--watch-preview-interrupted") }
        app.launch()
        guard app.descendants(matching: .any)["watchPreviewFixture"].firstMatch.waitForExistence(timeout: 5) else {
            return XCTFail("Microphone-free preview was not enabled")
        }
        let action = app.buttons[interrupted ? "Continue" : "Record"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        XCTAssertFalse(action.isEnabled, "The permission preparation must be pending before departure")
        if dismiss {
            let done = app.buttons["Done"]
            for _ in 0..<4 where !done.isHittable { app.swipeUp() }
            XCTAssertTrue(done.isHittable)
            done.tap()
        } else {
            XCUIApplication(bundleIdentifier: "com.apple.NanoSettings").launch()
        }
        try await Task.sleep(for: .seconds(16))
        if !dismiss { app.activate() }
        let record = app.buttons["Record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(record.isEnabled, "Return must allow a new explicit recording attempt")
        XCTAssertFalse(app.buttons["Stop"].exists, "The old permission callback must not capture after departure")
        capture(interrupted ? "Watch cancelled Continue" : "Watch cancelled Start")
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDeniedLocalMicrophoneAndOfflineRemoteExplainRecoveryBeforeRecording() {
        let app = XCUIApplication()
        app.launchArguments = ["--compatibility-denied-fixture"]
        app.launch()
        let local = app.buttons["Record"]
        XCTAssertTrue(local.waitForExistence(timeout: 10))
        XCTAssertFalse(local.isEnabled, "Denied local microphone must block Record before a tap")
        let recovery = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Microphone access is off")).firstMatch
        XCTAssertTrue(recovery.exists)
        XCTAssertTrue(recovery.label.contains("Privacy & Security"))
        XCTAssertTrue(recovery.isHittable)
        let localShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        localShot.name = "Watch local microphone recovery"
        localShot.lifetime = .keepAlways
        add(localShot)
        app.swipeUp()
        let remote = app.buttons["Start"]
        XCTAssertTrue(remote.waitForExistence(timeout: 5))
        XCTAssertFalse(remote.isEnabled, "An offline phone must not offer remote capture")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Watch offline remote"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
