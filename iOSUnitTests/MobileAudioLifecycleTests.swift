import AVFoundation
import SwiftUI
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Interruptions, route changes and backgrounding used to be wired into `ListenToMeIOSApp.body`,
/// where no test could reach them. They now live on `MobileSession` and take plain values.
@MainActor
final class MobileAudioLifecycleTests: XCTestCase {
    private func makeSession(_ recorder: LifecycleTestRecorder) -> (MobileSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (MobileSession(storageDirectory: root, makeRecorder: { recorder }), root)
    }

    private func record(_ session: MobileSession) async throws {
        session.start()
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
    }

    func testInterruptionStopsRecordingWithAMessageAndResumesWhenTheSystemSaysItShould() async throws {
        let recorder = LifecycleTestRecorder()
        let (session, root) = makeSession(recorder)
        defer { try? FileManager.default.removeItem(at: root) }
        try await record(session)

        await session.handleInterruption(.began)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.stopReason, .interruption)
        let stopMessage = try XCTUnwrap(session.message)
        XCTAssertTrue(stopMessage.lowercased().contains("interrupt"), stopMessage)
        XCTAssertEqual(recorder.stopCount, 1)

        await session.handleInterruption(.ended, options: .shouldResume)
        for _ in 0..<400 where session.state != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(recorder.startCount, 2)
        XCTAssertNil(session.stopReason)
    }

    func testInterruptionWithoutShouldResumeLeavesTheSessionStoppedAndExplainsHowToContinue() async throws {
        let recorder = LifecycleTestRecorder()
        let (session, root) = makeSession(recorder)
        defer { try? FileManager.default.removeItem(at: root) }
        try await record(session)

        await session.handleInterruption(.began)
        await session.handleInterruption(.ended, options: [])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertTrue(try XCTUnwrap(session.message).contains("Listen"))
    }

    func testBackgroundingStopsWithAMessageAndAResumableInterruptionDoesNotRestartIt() async throws {
        let recorder = LifecycleTestRecorder()
        let (session, root) = makeSession(recorder)
        defer { try? FileManager.default.removeItem(at: root) }
        try await record(session)

        await session.handleScenePhase(.background)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.stopReason, .background)
        XCTAssertTrue(try XCTUnwrap(session.message).lowercased().contains("background"))

        // A stale interruption end must not silently re-open the microphone from the background.
        await session.handleInterruption(.ended, options: .shouldResume)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(recorder.startCount, 1)
    }

    func testConnectingAMicrophoneMidRecordingRebuildsCaptureInsteadOfStalling() async throws {
        let recorder = LifecycleTestRecorder()
        let (session, root) = makeSession(recorder)
        defer { try? FileManager.default.removeItem(at: root) }
        try await record(session)

        await session.handleRouteChange(.newDeviceAvailable)
        XCTAssertEqual(recorder.reconfigureCount, 1)
        XCTAssertEqual(session.state, .recording)
        XCTAssertTrue(try XCTUnwrap(session.message).lowercased().contains("microphone"))

        // Losing a headset re-arms on the remaining input rather than ending the meeting.
        await session.handleRouteChange(.oldDeviceUnavailable)
        XCTAssertEqual(recorder.reconfigureCount, 2)
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(recorder.stopCount, 0)
    }

    func testARouteChangeThatCannotRestartCaptureStopsWithAMessage() async throws {
        let recorder = LifecycleTestRecorder()
        let (session, root) = makeSession(recorder)
        defer { try? FileManager.default.removeItem(at: root) }
        try await record(session)

        recorder.reconfigureError = RecordingError.message("No usable microphone is connected.")
        await session.handleRouteChange(.oldDeviceUnavailable)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.stopReason, .routeLost)
        XCTAssertTrue(try XCTUnwrap(session.message).contains("No usable microphone is connected."))
    }

    func testIdleSessionsIgnoreEveryAudioSessionEvent() async throws {
        let recorder = LifecycleTestRecorder()
        let (session, root) = makeSession(recorder)
        defer { try? FileManager.default.removeItem(at: root) }
        await session.handleInterruption(.began)
        await session.handleRouteChange(.newDeviceAvailable)
        XCTAssertNil(session.message)
        XCTAssertNil(session.stopReason)
        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(recorder.reconfigureCount, 0)
    }

    func testNotificationPayloadsAreDecodedIntoPlainValues() throws {
        let interruption = Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ])
        let event = try XCTUnwrap(MobileSession.interruption(from: interruption))
        XCTAssertEqual(event.type, .ended)
        XCTAssertTrue(event.options.contains(.shouldResume))
        XCTAssertNil(MobileSession.interruption(from: Notification(name: AVAudioSession.interruptionNotification)))

        let route = Notification(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
        ])
        XCTAssertEqual(MobileSession.routeChangeReason(from: route), .newDeviceAvailable)
        XCTAssertNil(MobileSession.routeChangeReason(from: Notification(name: AVAudioSession.routeChangeNotification)))
    }
}

@MainActor
final class LifecycleTestRecorder: MobileRecording {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var reconfigureCount = 0
    var reconfigureError: (any Error)?

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { startCount += 1 }
    func stop() async throws { stopCount += 1 }
    func reconfigure() async throws {
        reconfigureCount += 1
        if let reconfigureError { throw reconfigureError }
    }
}
