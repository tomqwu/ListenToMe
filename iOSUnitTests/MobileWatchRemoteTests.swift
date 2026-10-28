import SwiftUI
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// The Apple Watch remote (issue #181): the phone answers Start, Stop and Status, and never touches
/// the microphone unless the app is active in the foreground.
@MainActor
final class MobileWatchRemoteTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func waitForState(_ session: MobileSession, _ state: MobileSession.State) async throws {
        for _ in 0..<400 where session.state != state { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.state, state)
    }

    func testStartFromWatchWhileNotActiveNeverCreatesARecorder() async {
        var made = 0
        let session = MobileSession(storageDirectory: root, makeRecorder: { made += 1; return LifecycleTestRecorder() })
        session.applicationIsActive = { false }
        let reply = await session.handleWatchCommand(.start)
        XCTAssertEqual(reply, .openPhoneApp)
        XCTAssertEqual(made, 0)
        XCTAssertEqual(session.state, .idle)
    }

    func testUnsupportedPhoneSpeechRefusesWatchStartWithReasonAndNoRecorder() async {
        var made = 0
        let session = MobileSession(storageDirectory: root, makeRecorder: {
            made += 1; return LifecycleTestRecorder()
        }, recordingSupport: { _ in .unsupported(reason: "Choose a supported language on iPhone.") })
        session.applicationIsActive = { true }
        let reply = await session.handleWatchCommand(.start)
        XCTAssertEqual(reply, .busy("Choose a supported language on iPhone."))
        XCTAssertEqual(made, 0)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.phoneRecorderStatus.recordingReady, false)
        XCTAssertEqual(session.phoneRecorderStatus.recordingUnavailableReason, "Choose a supported language on iPhone.")
    }

    func testStartFromWatchWhileActiveStartsAndPublishesRecording() async throws {
        let recorder = LifecycleTestRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        let link = FakeWatchLink()
        session.watchLink = link
        session.applicationIsActive = { true }

        let reply = await session.handleWatchCommand(.start)
        guard case .accepted(let status) = reply else { return XCTFail("Expected accepted, got \(reply)") }
        XCTAssertEqual(status.state, .preparing)
        XCTAssertEqual(status.title, session.title)
        try await waitForState(session, .recording)
        XCTAssertEqual(recorder.startCount, 1)
        let last = try XCTUnwrap(link.published.last)
        XCTAssertEqual(last.state, .recording)
        XCTAssertNotNil(last.startedAt)
        XCTAssertEqual(last.startedAt, session.recordingStartedAt)
    }

    func testStopFromWatchStopsAndPublishesIdle() async throws {
        let recorder = LifecycleTestRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        let link = FakeWatchLink()
        session.watchLink = link
        session.applicationIsActive = { true }
        _ = await session.handleWatchCommand(.start)
        try await waitForState(session, .recording)

        let startedAt = session.recordingStartedAt
        let reply = await session.handleWatchCommand(.stop)
        // Answered as stopping; the idle status follows as the application context.
        XCTAssertEqual(reply, .accepted(PhoneRecorderStatus(state: .stopping, startedAt: startedAt,
                                                            title: session.title, lastStopReason: nil, recordingReady: true)))
        try await waitForState(session, .idle)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertNil(session.recordingStartedAt)
        let idle = PhoneRecorderStatus(state: .idle, startedAt: nil, title: session.title, lastStopReason: .user, recordingReady: true)
        XCTAssertEqual(link.published.last, idle)
    }

    /// Finalizing a long transcript can outlast the watch's reply timeout, so Stop is answered first.
    func testStopFromWatchAnswersBeforeTheTranscriptIsFinalized() async throws {
        let recorder = SlowStopRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        let link = FakeWatchLink()
        session.watchLink = link
        session.applicationIsActive = { true }
        _ = await session.handleWatchCommand(.start)
        try await waitForState(session, .recording)

        var reply: WatchReply?
        let command = Task { reply = await session.handleWatchCommand(.stop) }
        for _ in 0..<400 where reply == nil || !recorder.isStopping { try await Task.sleep(for: .milliseconds(5)) }
        let answered = reply
        recorder.finishStop()
        await command.value

        guard case .accepted(let status) = answered else { return XCTFail("Stop was not answered while finalizing") }
        XCTAssertEqual(status.state, .stopping)
        try await waitForState(session, .idle)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(link.published.last?.state, .idle)
    }

    func testStartWhileSummarizingRepliesBusy() async {
        var made = 0
        let session = MobileSession(storageDirectory: root, makeRecorder: { made += 1; return LifecycleTestRecorder() })
        session.applicationIsActive = { true }
        session.isSummarizing = true
        let reply = await session.handleWatchCommand(.start)
        XCTAssertEqual(reply, .busy("Generating a summary on iPhone"))
        XCTAssertEqual(made, 0)
        XCTAssertEqual(session.state, .idle)
    }

    func testBackgroundKeepsWatchRecordingStatusAndElapsedStartUntilStop() async throws {
        let recorder = LifecycleTestRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        let link = FakeWatchLink()
        session.watchLink = link
        session.applicationIsActive = { true }
        _ = await session.handleWatchCommand(.start)
        try await waitForState(session, .recording)

        await session.handleScenePhase(.background)
        let last = try XCTUnwrap(link.published.last)
        XCTAssertEqual(last.state, .recording)
        XCTAssertNil(last.lastStopReason)
        XCTAssertEqual(last.startedAt, session.recordingStartedAt)
        XCTAssertNotNil(last.startedAt)
        XCTAssertEqual(last.recordingReady, false, "Background cannot start another recording")
        await session.stop()
    }

    func testStatusCommandReportsWithoutTouchingTheRecorder() async {
        var made = 0
        let session = MobileSession(storageDirectory: root, makeRecorder: { made += 1; return LifecycleTestRecorder() })
        for active in [true, false] {
            session.applicationIsActive = { active }
            let reply = await session.handleWatchCommand(.status)
            XCTAssertEqual(reply, .accepted(PhoneRecorderStatus(state: .idle, startedAt: nil, title: session.title,
                                                                lastStopReason: nil, recordingReady: active,
                                                                recordingUnavailableReason: active ? nil
                                                                    : "Open ListenToMe on your iPhone to record")))
        }
        XCTAssertEqual(made, 0)
        XCTAssertEqual(session.state, .idle)
    }

    func testPublishWatchStatusSendsTheCurrentStatus() {
        let session = MobileSession(storageDirectory: root, makeRecorder: { LifecycleTestRecorder() })
        let link = FakeWatchLink()
        session.watchLink = link
        session.publishWatchStatus()
        XCTAssertEqual(link.published, [session.phoneRecorderStatus])
    }

    /// The watch keeps showing "Open ListenToMe…" or a busy reply until a newer status arrives, so the
    /// phone republishes when it becomes active and when a summary starts or ends.
    func testActivePhaseAndSummaryChangesRepublishTheStatus() async {
        let session = MobileSession(storageDirectory: root, makeRecorder: { LifecycleTestRecorder() })
        let link = FakeWatchLink()
        session.watchLink = link
        await session.handleScenePhase(.active)
        XCTAssertEqual(link.published, [session.phoneRecorderStatus])
        session.isSummarizing = true
        XCTAssertEqual(link.published.count, 2)
        session.isSummarizing = false
        XCTAssertEqual(link.published.count, 3)
        session.isSummarizing = false
        XCTAssertEqual(link.published.count, 3, "No change, nothing to publish")
    }

    /// The watch drops a reply older than the status it already shows, so every reply is stamped.
    func testRepliesAreStampedWithWhenTheyWereMade() async throws {
        let before = Date().timeIntervalSince1970
        let reply = await PhoneWatchLink.replyMessage(to: WatchLink.message(for: .status), handler: { _ in .openPhoneApp })
        let stamp = try XCTUnwrap(WatchLink.stamp(from: reply))
        XCTAssertGreaterThanOrEqual(stamp, before)
        XCTAssertLessThanOrEqual(stamp, Date().timeIntervalSince1970)
        let unsupported = await PhoneWatchLink.replyMessage(to: ["v": 2], handler: nil)
        XCTAssertNotNil(WatchLink.stamp(from: unsupported))
    }

    func testLinkWithoutAnAttachedSessionAnswersOpenPhoneApp() async {
        let reply = await PhoneWatchLink.replyMessage(to: WatchLink.message(for: .start), handler: nil)
        XCTAssertEqual(try WatchLink.reply(from: reply), .openPhoneApp)
    }

    func testUnknownProtocolVersionAnswersUnsupportedVersion() async {
        let reply = await PhoneWatchLink.replyMessage(to: ["v": 2, "cmd": "start"], handler: { _ in .openPhoneApp })
        XCTAssertEqual(try WatchLink.reply(from: reply), .unsupportedVersion)
    }

    func testAttachedHandlerAnswersAndMalformedCommandsDoNotReachIt() async {
        var received: [WatchCommand] = []
        let handler: @MainActor (WatchCommand) async -> WatchReply = { received.append($0); return .busy("x") }
        let reply = await PhoneWatchLink.replyMessage(to: WatchLink.message(for: .stop), handler: handler)
        XCTAssertEqual(try WatchLink.reply(from: reply), .busy("x"))
        let malformed = await PhoneWatchLink.replyMessage(to: ["v": 1, "cmd": "erase"], handler: handler)
        // Same version but an unknown command means the two builds disagree.
        XCTAssertEqual(try WatchLink.reply(from: malformed), .unsupportedVersion)
        XCTAssertEqual(received, [.stop])
    }
}

/// Slice 3: the iPhone shows when the Apple Watch itself is recording. It records nothing itself.
extension MobileWatchRemoteTests {
    func testWatchContextSetsTheRecordingLine() {
        var made = 0
        let session = MobileSession(storageDirectory: root, makeRecorder: { made += 1; return LifecycleTestRecorder() })
        XCTAssertNil(session.watchCaptureStatus)
        let recording = WatchCaptureStatus(state: .recording, startedAt: Date(timeIntervalSince1970: 1_000),
                                           waitingRecordings: 1)
        session.receiveWatchContext(WatchLink.context(for: recording))
        XCTAssertEqual(session.watchCaptureStatus, recording)
        XCTAssertEqual(WatchRemoteText.watchRecordingLine(session.watchCaptureStatus,
                                                          now: Date(timeIntervalSince1970: 1_065)),
                       "Apple Watch is recording · 01:05")

        var future = WatchLink.context(for: WatchCaptureStatus(state: .idle, startedAt: nil, waitingRecordings: 0))
        future["v"] = 2
        session.receiveWatchContext(future)
        XCTAssertEqual(session.watchCaptureStatus, recording, "Another protocol version changes nothing")
        session.receiveWatchContext([:])
        XCTAssertEqual(session.watchCaptureStatus, recording)

        let idle = WatchCaptureStatus(state: .idle, startedAt: nil, waitingRecordings: 0)
        session.receiveWatchContext(WatchLink.context(for: idle))
        XCTAssertEqual(session.watchCaptureStatus, idle)
        XCTAssertNil(WatchRemoteText.watchRecordingLine(session.watchCaptureStatus, now: Date()))
        XCTAssertEqual(made, 0, "The phone records nothing while the watch records")
        XCTAssertEqual(session.state, .idle)
    }
}
