import XCTest

@MainActor
final class WatchCapabilityUITests: XCTestCase {
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
