import AVFoundation
import XCTest

final class MacMicrophoneCaptureTests: XCTestCase {
    private final class Driver: MacMicrophoneDriving, @unchecked Sendable {
        var isRunning = false
        var profileMatches = true
        var isHealthy: Bool { isRunning && profileMatches }
        var events: [String] = []
        var failEcho = false, failStart = false, failTap = false
        var installedTap = false
        var onStart: (@Sendable () -> Void)?
        func enableEchoCancellation() throws {
            events.append("echo"); profileMatches = true
            if failEcho { throw NSError(domain: "test", code: 1) }
        }
        func installTap(_ receive: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
            events.append("tap")
            if failTap { throw NSError(domain: "test", code: 2) }
            installedTap = true
        }
        func start() throws {
            events.append("start"); onStart?()
            if failStart { throw NSError(domain: "test", code: 3) }
            isRunning = true
        }
        func tearDown() { events.append("stop"); isRunning = false; installedTap = false }
    }

    func testListeningEnablesEchoControlBeforeReadingFormatAndInstallingTap() throws {
        let driver = Driver()
        let actual = MacMicrophoneCapture(driver: driver) { _, _ in }
        try actual.start()
        XCTAssertEqual(driver.events, ["echo", "tap", "start"])
        XCTAssertTrue(driver.isRunning)
        actual.stop()
        XCTAssertFalse(driver.isRunning)
        XCTAssertFalse(driver.installedTap)
    }

    func testEchoFailureNeverStartsAnUnprotectedMicrophoneAndStartFailureCleansTap() {
        for failure in ["echo", "tap", "start"] {
            let driver = Driver()
            driver.failEcho = failure == "echo"; driver.failTap = failure == "tap"; driver.failStart = failure == "start"
            let capture = MacMicrophoneCapture(driver: driver) { _, _ in }
            XCTAssertThrowsError(try capture.start(), failure)
            XCTAssertFalse(driver.isRunning)
            XCTAssertFalse(driver.installedTap, failure)
            XCTAssertEqual(driver.events.last, "stop", failure)
            if failure == "echo" { XCTAssertFalse(driver.events.contains("tap")); XCTAssertFalse(driver.events.contains("start")) }
        }
    }

    func testHealthyConfigurationNotificationDoesNotRestartAndStopCannotResurrectCapture() throws {
        let driver = Driver()
        let actual = MacMicrophoneCapture(driver: driver) { _, _ in }
        try actual.start()
        let events = driver.events
        XCTAssertFalse(try actual.recoverIfNeeded())
        XCTAssertEqual(driver.events, events)
        driver.isRunning = false
        XCTAssertTrue(try actual.recoverIfNeeded())
        XCTAssertEqual(Array(driver.events.suffix(4)), ["stop", "echo", "tap", "start"])
        actual.stop()
        let stoppedEvents = driver.events
        XCTAssertFalse(try actual.recoverIfNeeded())
        XCTAssertThrowsError(try actual.start())
        XCTAssertEqual(driver.events, stoppedEvents)
        XCTAssertFalse(driver.isRunning)
    }
    func testRunningEngineWithChangedRouteOrVoiceProfileRebuildsItsTap() throws {
        let driver = Driver()
        let capture = MacMicrophoneCapture(driver: driver) { _, _ in }
        try capture.start()
        driver.profileMatches = false
        XCTAssertTrue(driver.isRunning)
        XCTAssertTrue(try capture.recoverIfNeeded())
        XCTAssertEqual(Array(driver.events.suffix(4)), ["stop", "echo", "tap", "start"])
        XCTAssertTrue(driver.isHealthy)
        capture.stop()
    }

    func testStopDuringEngineStartCleansUpBeforeReturningAndQueuedRecoveryStaysStopped() throws {
        let driver = Driver(), entered = DispatchSemaphore(value: 0), proceed = DispatchSemaphore(value: 0)
        driver.onStart = { entered.signal(); _ = proceed.wait(timeout: .now() + 5) }
        let capture = MacMicrophoneCapture(driver: driver) { _, _ in }
        let started = expectation(description: "Start cancelled"), stopped = expectation(description: "Stop completed")
        DispatchQueue.global().async {
            do { try capture.start(); XCTFail("Start completed after Stop") }
            catch { XCTAssertTrue(error is CancellationError) }
            started.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async { capture.stop(); stopped.fulfill() }
        let deadline = Date().addingTimeInterval(5)
        while !capture.isStopped && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertTrue(capture.isStopped)
        proceed.signal()
        wait(for: [started, stopped], timeout: 5)
        XCTAssertFalse(driver.isRunning)
        XCTAssertFalse(driver.installedTap)
        XCTAssertFalse(try capture.recoverIfNeeded())
        XCTAssertThrowsError(try capture.start())
    }

    private final class Clock: @unchecked Sendable {
        var time: TimeInterval = 10
    }

    func testSecondRouteFailureDuringCooldownStopsUnsafeInputThenRecoversUnlessStopped() throws {
        let driver = Driver(), clock = Clock()
        let capture = MacMicrophoneCapture(driver: driver, now: { clock.time }) { _, _ in }
        try capture.start()
        driver.profileMatches = false
        XCTAssertTrue(try capture.recoverIfNeeded())
        driver.profileMatches = false
        XCTAssertThrowsError(try capture.recoverIfNeeded()) { XCTAssertTrue($0 is MacMicrophoneRecoveryDeferred) }
        XCTAssertFalse(driver.isRunning, "Never leave an unprotected running input during cooldown")
        clock.time += 0.5
        XCTAssertTrue(try capture.recoverIfNeeded())
        XCTAssertTrue(driver.isHealthy)
        driver.profileMatches = false
        XCTAssertThrowsError(try capture.recoverIfNeeded())
        capture.stop()
        clock.time += 0.5
        XCTAssertFalse(try capture.recoverIfNeeded())
        XCTAssertFalse(driver.isRunning)
    }

}
