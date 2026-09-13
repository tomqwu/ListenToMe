import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileAutomaticSummaryTests: XCTestCase {
    func testStartReceivesSpeechAndCatchesUpAfterSlowResponseWithoutNewSpeech() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SlowSummaryProvider()
        let recorder = TestRecorder()
        let session = MobileSession(storageDirectory: root, summaryProvider: provider,
                                    autoInterval: .milliseconds(100), makeRecorder: { recorder })
        let originalAuto = session.autoQuick
        let originalCorrection = session.ai.correctTranscript
        defer {
            session.state = .idle; session.autoQuick = originalAuto
            session.ai.correctTranscript = originalCorrection
        }
        session.ai.correctTranscript = false
        session.autoQuick = true
        session.start()
        try await waitUntil { session.state == .recording && session.quickReader.isReading }
        try await waitUntil { await provider.hasPendingFirst() }
        XCTAssertEqual(session.segments.first?.text, "First phrase")
        recorder.send("Second phrase")
        // Hold the first response past the cooldown. No speech callback follows its completion.
        try await Task.sleep(for: .milliseconds(150))
        let finished = await provider.finishFirst()
        XCTAssertTrue(finished, "The provider must have received the first request before it is released")
        // Exact catch-up deadlines are asserted with an injected clock in LiveSummarySchedulerTests.
        // This integration check waits for the event-driven result without requiring CI to run within one second.
        try await waitUntil { session.quickSummary.contains("Second phrase") }
        let requests = await provider.count()
        XCTAssertEqual(requests, 2)
        XCTAssertTrue(session.autoQuickStatus.contains("Up to date"))
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(recorder.stopped)
        XCTAssertEqual(MobileSession(storageDirectory: root).quickSummary, session.quickSummary)
    }

    func testManualQuickHidesModelPlanningAndKeepsOnlyValidatedBullets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let response = """
        The user wants a recap. Let me count words and reason about the instructions.
        {"action":"publish","context":"Peter Wednesday","bullets":["Peter delivers Wednesday."],"reviews":[]}
        """
        let session = MobileSession(storageDirectory: root,
            summaryProvider: ManualQuickPlanningProvider(response: response))
        session.notes = "Peter delivers Wednesday."
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "- Peter delivers Wednesday.")
        XCTAssertFalse(session.markdown.contains("count words"))
        XCTAssertFalse(session.markdown.contains("\"action\""))
    }

    func testSharingOlderAndLegacyRecordsPreservesChosenContentAndActiveSession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.title = "Older meeting"
        session.notes = "Older notes"
        session.summary = "Older summary"
        session.quickSummary = "Older quick"
        session.deepThought = "Older deep"
        session.segments = [.init(source: .you, text: "Older speech", isFinal: true, start: 0, end: 1)]
        session.save()
        let record = try XCTUnwrap(session.history.first)
        session.newConversation()
        session.notes = "Current notes"
        let currentID = session.id
        let export = MobileSession.markdown(for: record)
        for text in ["Older meeting", "Older notes", "Older summary", "Older quick", "Older deep", "Older speech"] {
            XCTAssertTrue(export.contains(text))
        }
        XCTAssertFalse(export.contains("Current notes"))
        XCTAssertEqual(session.id, currentID)
        XCTAssertEqual(session.notes, "Current notes")
        let legacy = SessionRecord(id: "legacy", title: "Legacy", date: Date(), transcript: "Legacy speech", summary: "Recap")
        XCTAssertTrue(MobileSession.markdown(for: legacy).contains("Legacy speech"))
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let satisfied = await predicate()
        XCTAssertTrue(satisfied)
    }
}

@MainActor
private final class TestRecorder: MobileRecording {
    private var receive: (@MainActor (TranscriptSegment) -> Void)?
    var stopped = false
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        receive = onSegment
        send("First phrase")
    }
    func send(_ text: String) { receive?(.init(source: .you, text: text, isFinal: true, start: 0, end: 1)) }
    func stop() async throws { stopped = true; receive = nil }
}

private actor SlowSummaryProvider: LLMProvider {
    nonisolated let id = "slow-summary-test"
    private var requests = 0
    private var first: AsyncThrowingStream<String, Error>.Continuation?
    func count() -> Int { requests }
    func hasPendingFirst() -> Bool { first != nil }
    func finishFirst() -> Bool {
        guard let first else { return false }
        first.yield("{\"reviews\":[],\"action\":\"publish\",\"context\":\"First phrase\",\"bullets\":[\"First summary\"]}")
        first.finish(); self.first = nil
        return true
    }
    private func respond(_ request: LLMRequest, to continuation: AsyncThrowingStream<String, Error>.Continuation) {
        requests += 1
        if requests == 1 { first = continuation } else {
            continuation.yield("{\"reviews\":[],\"action\":\"publish\",\"context\":\"First and second phrases\",\"bullets\":[\"Second phrase\"]}")
            continuation.finish()
        }
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(request, to: continuation) } }
    }
}

private struct ManualQuickPlanningProvider: LLMProvider {
    let id = "glm-style-response"
    let response: String
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield(response); $0.finish() }
    }
}
