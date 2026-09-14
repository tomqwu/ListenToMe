import XCTest
@testable import ListenToMeCore

/// Decision tables behind issue #107 (recover from an input-device change / SCStream stop) and
/// issue #110 (never start capture when the microphone is denied). The AVFoundation and
/// ScreenCaptureKit glue lives in App/DualChannelCapture.swift; everything decidable lives here.
final class CaptureRecoveryTests: XCTestCase {

    // MARK: - #110 microphone pre-flight

    func testAuthorizedMicrophoneStarts() {
        XCTAssertEqual(CapturePreflight.decide(microphone: .authorized), .start)
    }

    func testNotDeterminedMicrophoneRequestsAccessFirst() {
        XCTAssertEqual(CapturePreflight.decide(microphone: .notDetermined), .requestAccess)
    }

    func testDeniedMicrophoneBlocksWithSettingsPath() {
        guard case .blocked(let message, let canOpenSettings) =
                CapturePreflight.decide(microphone: .denied) else {
            return XCTFail("denied microphone must block the start")
        }
        XCTAssertTrue(canOpenSettings)
        XCTAssertTrue(message.contains("System Settings"))
        XCTAssertEqual(message, CapturePreflight.deniedMessage)
    }

    func testRestrictedMicrophoneBlocksWithoutSettingsPath() {
        // A device-management/Screen Time restriction cannot be lifted from the user's own
        // Privacy pane, so don't send them there.
        guard case .blocked(let message, let canOpenSettings) =
                CapturePreflight.decide(microphone: .restricted) else {
            return XCTFail("restricted microphone must block the start")
        }
        XCTAssertFalse(canOpenSettings)
        XCTAssertEqual(message, CapturePreflight.restrictedMessage)
    }

    func testGrantedPromptAnswerStartsAndDeniedAnswerBlocks() {
        XCTAssertEqual(CapturePreflight.decideAfterRequest(granted: true), .start)
        XCTAssertEqual(CapturePreflight.decideAfterRequest(granted: false),
                       .blocked(message: CapturePreflight.deniedMessage, canOpenSettings: true))
    }

    func testNoAccessStatusIsDegradedAndNotClaimingActive() {
        let status = CapturePreflight.noAccessStatus
        XCTAssertEqual(status.source, .you)
        XCTAssertEqual(status.severity, .degraded)
        XCTAssertNotEqual(status.message, "active")
    }

    // MARK: - #107 restart policy

    func testMicrophoneRestartIsAttemptedOnceUntilItSucceeds() {
        var policy = CaptureRecovery.Policy()
        XCTAssertTrue(policy.shouldAttemptRestart(for: .you, now: 0))
        XCTAssertFalse(policy.shouldAttemptRestart(for: .you, now: 0), "a failed restart must not loop")
        policy.restartSucceeded(for: .you, now: 0)
        XCTAssertTrue(policy.shouldAttemptRestart(for: .you, now: 10),
                      "a later change gets a fresh attempt")
    }

    func testRestartBudgetsAreIndependentPerSource() {
        var policy = CaptureRecovery.Policy()
        XCTAssertTrue(policy.shouldAttemptRestart(for: .you, now: 0))
        XCTAssertTrue(policy.shouldAttemptRestart(for: .others, now: 0))
        XCTAssertFalse(policy.shouldAttemptRestart(for: .others, now: 0))
        policy.restartSucceeded(for: .others, now: 0)
        XCTAssertTrue(policy.shouldAttemptRestart(for: .others, now: 10))
        XCTAssertFalse(policy.shouldAttemptRestart(for: .you, now: 10))
    }

    func testFlappingDeviceCannotSustainARestartLoop() {
        // A device that connects/disconnects repeatedly would otherwise re-arm the budget on every
        // success and restart the engine forever; changes inside the floor window are ignored.
        var policy = CaptureRecovery.Policy()
        XCTAssertTrue(policy.shouldAttemptRestart(for: .you, now: 100))
        policy.restartSucceeded(for: .you, now: 100)
        let insideFloor = 100 + CaptureRecovery.Policy.restartFloor / 2
        XCTAssertFalse(policy.shouldAttemptRestart(for: .you, now: insideFloor))
        let pastFloor = 100 + CaptureRecovery.Policy.restartFloor + 0.01
        XCTAssertTrue(policy.shouldAttemptRestart(for: .you, now: pastFloor))
    }

    func testFloorIsPerChannel() {
        var policy = CaptureRecovery.Policy()
        XCTAssertTrue(policy.shouldAttemptRestart(for: .you, now: 0))
        policy.restartSucceeded(for: .you, now: 0)
        XCTAssertTrue(policy.shouldAttemptRestart(for: .others, now: 0),
                      "a fresh mic restart must not block the system-audio channel")
    }

    func testStoppedCaptureRefusesEveryRestart() {
        // A configuration-change notification can fire while stop() is tearing the engine down;
        // once the capture is stopped nothing may bring the microphone back up.
        var policy = CaptureRecovery.Policy()
        policy.markStopped()
        XCTAssertFalse(policy.shouldAttemptRestart(for: .you, now: 0))
        XCTAssertFalse(policy.shouldAttemptRestart(for: .others, now: 0))
        policy.restartSucceeded(for: .you, now: 0)
        XCTAssertFalse(policy.shouldAttemptRestart(for: .you, now: 100),
                       "a stopped capture stays stopped")
    }

    // MARK: - #107 status messages

    func testResumedMicrophoneStatusIsNormal() {
        let status = CaptureRecovery.status(for: .microphoneInputChanged, outcome: .resumed)
        XCTAssertEqual(status.source, .you)
        XCTAssertEqual(status.severity, .normal)
        XCTAssertEqual(status.message, "input changed — resumed")
    }

    func testFailedMicrophoneRestartIsDegradedAndNamesTheReason() {
        let status = CaptureRecovery.status(for: .microphoneInputChanged,
                                            outcome: .failed(reason: "no input device"))
        XCTAssertEqual(status.source, .you)
        XCTAssertEqual(status.severity, .degraded)
        XCTAssertTrue(status.message.contains("no input device"), status.message)
        XCTAssertTrue(status.message.contains("stopped"), status.message)
    }

    func testUnattemptedMicrophoneRestartIsDegraded() {
        let status = CaptureRecovery.status(for: .microphoneInputChanged, outcome: .notAttempted)
        XCTAssertEqual(status.severity, .degraded)
        XCTAssertTrue(status.message.contains("Stop and restart"), status.message)
    }

    func testResumedSystemAudioStatusIsNormal() {
        let status = CaptureRecovery.status(for: .systemAudioStopped(reason: "display changed"),
                                            outcome: .resumed)
        XCTAssertEqual(status.source, .others)
        XCTAssertEqual(status.severity, .normal)
        XCTAssertEqual(status.message, "system audio stopped — resumed")
    }

    func testFailedSystemAudioRestartIsDegradedAndKeepsBothReasons() {
        let status = CaptureRecovery.status(for: .systemAudioStopped(reason: "display changed"),
                                            outcome: .failed(reason: "no display available"))
        XCTAssertEqual(status.source, .others)
        XCTAssertEqual(status.severity, .degraded)
        XCTAssertTrue(status.message.contains("display changed"), status.message)
        XCTAssertTrue(status.message.contains("no display available"), status.message)
    }

    func testUnattemptedSystemAudioRestartIsDegraded() {
        let status = CaptureRecovery.status(for: .systemAudioStopped(reason: "display changed"),
                                            outcome: .notAttempted)
        XCTAssertEqual(status.source, .others)
        XCTAssertEqual(status.severity, .degraded)
        XCTAssertTrue(status.message.contains("display changed"), status.message)
        XCTAssertTrue(status.message.contains("Stop and restart"), status.message)
    }

    func testPlainStatusesDefaultToNormalSeverity() {
        XCTAssertEqual(CaptureStatus(source: .you, message: "active").severity, .normal)
    }
}

/// The session-level flag the UI uses to show a visible (red) capture-degraded banner instead of
/// a grey caption while the rail still says Recording (issue #107).
@MainActor
final class CaptureDegradedSessionTests: XCTestCase {

    private func makeSession(capture: MockCapture) -> MeetingSession {
        MeetingSession(store: ConversationStore(),
                       context: ContextEngine(debounce: 0),
                       makeCapture: { capture },
                       makeTranscriber: { MockTranscriber() },
                       makeProvider: { model in MockLLMProvider(id: model, deltas: ["ok"]) },
                       models: [.listener: "L", .quick: "Q", .deep: "D"],
                       listenerDebounce: 0)
    }

    func testDegradedStatusRaisesAndClearsTheFlag() async {
        let capture = MockCapture()
        let session = makeSession(capture: capture)
        try? await session.start()
        XCTAssertFalse(session.captureDegraded)

        capture.emitStatus(CaptureRecovery.status(for: .microphoneInputChanged,
                                                  outcome: .failed(reason: "no input device")))
        await waitFor { session.captureDegraded }
        XCTAssertTrue(session.captureStatus.contains("no input device"))

        capture.emitStatus(CaptureRecovery.status(for: .microphoneInputChanged, outcome: .resumed))
        await waitFor { !session.captureDegraded }
    }

    func testOneHealthyChannelDoesNotClearTheOtherChannelsDegradation() async {
        let capture = MockCapture()
        let session = makeSession(capture: capture)
        try? await session.start()

        capture.emitStatus(CaptureRecovery.status(for: .systemAudioStopped(reason: "boom"),
                                                  outcome: .notAttempted))
        await waitFor { session.captureDegraded }
        capture.emitStatus(CaptureStatus(source: .you, message: "active"))
        // Still degraded: the `.others` channel never recovered.
        XCTAssertTrue(session.captureDegraded)
        await session.stopAndWait()
        XCTAssertFalse(session.captureDegraded, "stopping clears the degraded banner")
    }

    private func waitFor(_ condition: @MainActor () -> Bool,
                         file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition not met in time", file: file, line: line)
    }
}
