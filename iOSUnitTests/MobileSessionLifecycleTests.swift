import SwiftUI
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileSessionLifecycleTests: XCTestCase {
    private var root: URL!
    private var defaults: [String: Any] = [:]

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("mobile") || $0.key == "autoQuickSummary" }
        UserDefaults.standard.set(false, forKey: MobileSpeakers.enabledKey)
        UserDefaults.standard.set(false, forKey: "autoQuickSummary")
    }

    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("mobile") || key == "autoQuickSummary" {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in defaults { UserDefaults.standard.set(value, forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }

    private func session(_ provider: LifecycleHeldProvider, recorder: LifecycleRecorder = LifecycleRecorder()) -> MobileSession {
        let session = MobileSession(storageDirectory: root, summaryProvider: provider,
                                    sharedInbox: root.appendingPathComponent("SharedInbox"),
                                    makeRecorder: { recorder }, recordingSupport: { _ in .ready })
        session.applicationIsActive = { true }
        session.renameByUser("Lifecycle check")
        session.autoQuick = false
        session.notes = "Keep this already requested answer when an obsolete phase delivery is cancelled."
        return session
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Expected the observable lifecycle outcome")
    }

    func testInactiveObservationCancelsOldAnswerAndReactivationKeepsNewAnswer() async throws {
        let provider = LifecycleHeldProvider()
        let session = session(provider)
        session.requestSummary()
        try await wait { await provider.started }
        let bridge = MobileSessionPhaseBridge(session: session)
        bridge.synchronize(.inactive)
        bridge.synchronize(.active)
        try await wait { await provider.cancelled }
        // Clean up on failure so the second half can still diagnose the fresh active request.
        if await !provider.cancelled { session.cancelSummary() }
        try await wait { !session.isSummarizing && !session.auxiliaryWorkSuspended }
        session.requestSummary()
        try await wait { await provider.calls == 2 }
        await provider.finish(call: 0, answer: "Obsolete answer must not appear.")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(session.summary.isEmpty)
        await provider.finish(call: 1)
        try await wait { !session.isSummarizing }
        XCTAssertEqual(session.summary, "The requested answer remains available.")
    }

    func testDetachedQueuedActiveDoesNotResumeOptionalWork() async throws {
        let provider = LifecycleHeldProvider()
        let session = session(provider)
        await session.handleScenePhase(.inactive)
        let bridge = MobileSessionPhaseBridge(session: session)
        bridge.synchronize(.active)
        bridge.detach()
        try await Task.sleep(for: .milliseconds(30))
        session.requestSummary()
        try await Task.sleep(for: .milliseconds(30))
        let started = await provider.started
        XCTAssertFalse(started, "A detached queued active delivery must not resume provider requests")
        XCTAssertTrue(session.auxiliaryWorkSuspended)
        await provider.finish()
    }

    func testDetachedBackgroundCancelsAnswerButKeepsEstablishedCapture() async throws {
        let provider = LifecycleHeldProvider()
        let recorder = LifecycleRecorder()
        let session = session(provider, recorder: recorder)
        await session.refreshRecordingSupport()
        session.start()
        try await wait { session.state == .recording }
        session.requestSummary()
        try await wait { await provider.started }
        let bridge = MobileSessionPhaseBridge(session: session)
        bridge.synchronize(.background)
        bridge.detach()
        try await wait { await provider.cancelled }
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(recorder.starts, 1)
        XCTAssertEqual(recorder.stops, 0)
        XCTAssertTrue(session.auxiliaryWorkSuspended)
        XCTAssertFalse(session.isForeground)
        await provider.finish()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(session.summary.isEmpty, "Late optional output must not publish after backgrounding")
        await session.stop()
        XCTAssertEqual(recorder.stops, 1)
    }

    func testBackgroundObservationRevokesPendingStartAcrossImmediateReactivation() async throws {
        let recorder = LifecycleRecorder()
        recorder.holdContext = true
        let session = session(LifecycleHeldProvider(), recorder: recorder)
        await session.refreshRecordingSupport()
        session.start()
        try await wait { recorder.contextHeld }
        XCTAssertEqual(session.state, .preparing)
        let bridge = MobileSessionPhaseBridge(session: session)
        bridge.synchronize(.background)
        bridge.synchronize(.active)
        recorder.releaseContext()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(session.state, .idle, "A real background observation revokes pending microphone intent")
        XCTAssertEqual(recorder.starts, 0, "A late preparation must not open a microphone after reactivation")
        await session.stop()
    }

    func testBackgroundObservationKeepsEstablishedCaptureAcrossImmediateReactivation() async throws {
        let provider = LifecycleHeldProvider()
        let recorder = LifecycleRecorder()
        let session = session(provider, recorder: recorder)
        await session.refreshRecordingSupport()
        session.start()
        try await wait { session.state == .recording }
        session.requestSummary()
        try await wait { await provider.started }
        let bridge = MobileSessionPhaseBridge(session: session)
        bridge.synchronize(.background)
        bridge.synchronize(.active)
        try await wait { await provider.cancelled }
        if await !provider.cancelled { session.cancelSummary() }
        await provider.finish()
        try await wait { !session.auxiliaryWorkSuspended && !session.isSummarizing }
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(recorder.starts, 1)
        XCTAssertEqual(recorder.stops, 0)
        XCTAssertTrue(session.summary.isEmpty)
        await session.stop()
    }

}

private actor LifecycleHeldProvider: LLMProvider {
    nonisolated let id = "lifecycle-held-no-network"
    private var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    var calls: Int { continuations.count }
    private(set) var started = false
    private(set) var cancelled = false

    private func markCancelled() { cancelled = true }

    private func hold(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        continuations.append(continuation)
        continuation.onTermination = { reason in
            if case .cancelled = reason { Task { await self.markCancelled() } }
        }
        started = true
    }

    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await self.hold(continuation) } }
    }

    func finish(call: Int = 0, answer: String = "The requested answer remains available.") {
        guard continuations.indices.contains(call) else { return }
        continuations[call].yield(answer)
        continuations[call].finish()
    }
}

@MainActor
private final class LifecycleRecorder: MobileRecording {
    var holdContext = false
    private var context: CheckedContinuation<Void, Never>?
    var contextHeld: Bool { context != nil }
    func setContextualStrings(_ strings: [String]) async {
        if holdContext { await withCheckedContinuation { context = $0 } }
    }
    func releaseContext() { context?.resume(); context = nil }
    private(set) var starts = 0
    private(set) var stops = 0
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws { starts += 1 }
    func stop() async throws { stops += 1 }
    func reconfigure() async throws {}
}
