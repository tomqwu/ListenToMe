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

        let reply = await session.handleWatchCommand(.stop)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertNil(session.recordingStartedAt)
        let idle = PhoneRecorderStatus(state: .idle, startedAt: nil, title: session.title, lastStopReason: .user)
        XCTAssertEqual(reply, .accepted(idle))
        XCTAssertEqual(link.published.last, idle)
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

    func testBackgroundStopPublishesTheBackgroundReason() async throws {
        let recorder = LifecycleTestRecorder()
        let session = MobileSession(storageDirectory: root, makeRecorder: { recorder })
        let link = FakeWatchLink()
        session.watchLink = link
        session.applicationIsActive = { true }
        _ = await session.handleWatchCommand(.start)
        try await waitForState(session, .recording)

        await session.handleScenePhase(.background)
        let last = try XCTUnwrap(link.published.last)
        XCTAssertEqual(last.state, .idle)
        XCTAssertEqual(last.lastStopReason, .background)
        XCTAssertNil(last.startedAt)
    }

    func testStatusCommandReportsWithoutTouchingTheRecorder() async {
        var made = 0
        let session = MobileSession(storageDirectory: root, makeRecorder: { made += 1; return LifecycleTestRecorder() })
        for active in [true, false] {
            session.applicationIsActive = { active }
            let reply = await session.handleWatchCommand(.status)
            XCTAssertEqual(reply, .accepted(PhoneRecorderStatus(state: .idle, startedAt: nil, title: session.title,
                                                                lastStopReason: nil)))
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
