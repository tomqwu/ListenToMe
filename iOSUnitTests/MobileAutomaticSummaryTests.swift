import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileAutomaticSummaryTests: XCTestCase {
    func testStartReceivesSpeechAndCatchesUpImmediatelyAfterSlowResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SlowSummaryProvider()
        let recorder = TestRecorder()
        let session = MobileSession(storageDirectory: root, summaryProvider: provider,
                                    autoInterval: .seconds(2), makeRecorder: { recorder })
        let originalAuto = session.autoQuick
        defer { session.state = .idle; session.autoQuick = originalAuto }
        session.autoQuick = true
        session.start()
        try await waitUntil { session.state == .recording && session.isSummarizing }
        XCTAssertEqual(session.segments.first?.text, "First phrase")
        recorder.send("Second phrase")
        // Hold the first response past the cooldown. No speech callback follows its completion.
        try await Task.sleep(for: .milliseconds(2100))
        await provider.finishFirst()
        try await waitUntil(timeout: .seconds(1)) { session.quickSummary.contains("Second phrase") }
        let requests = await provider.count()
        XCTAssertEqual(requests, 2)
        XCTAssertTrue(session.autoQuickStatus.contains("Up to date"))
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(recorder.stopped)
        XCTAssertEqual(MobileSession(storageDirectory: root).quickSummary, session.quickSummary)
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

    private func waitUntil(timeout: Duration = .seconds(3), _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate())
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
    func finishFirst() { first?.yield("First summary"); first?.finish(); first = nil }
    private func respond(_ request: LLMRequest, to continuation: AsyncThrowingStream<String, Error>.Continuation) {
        requests += 1
        if requests == 1 { first = continuation } else {
            continuation.yield(request.messages.last?.content ?? "")
            continuation.finish()
        }
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await respond(request, to: continuation) } }
    }
}
