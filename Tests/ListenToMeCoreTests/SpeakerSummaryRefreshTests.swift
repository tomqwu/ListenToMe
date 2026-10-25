import XCTest
@testable import ListenToMeCore

@MainActor
final class SpeakerSummaryRefreshTests: XCTestCase {
    private func session(_ provider: any LLMProvider) -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        var line = TranscriptSegment(source: .others, text: "The launch is on Friday.",
                                     isFinal: true, start: 0, end: 1)
        line.speakerID = "speaker"; line.speakerName = "Old name"
        store.apply(line)
        return (MeetingSession(store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "L", .quick: "Q", .deep: "D"]), store)
    }

    func testAttributionAndRenameDoNotCreateFirstSummaryWithAutoOff() async {
        let provider = RecordingProvider(deltas: ["Updated summary"])
        let (session, store) = session(provider)
        store.renameSpeaker(id: "speaker", name: "Dana")
        session.speakerAttributionsChanged()
        await session.waitForResponse(.listener)
        session.speakerNamesChanged()
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(session.listenerSummary.isEmpty)
        XCTAssertTrue(session.hasUnsummarizedSpeech)
        await session.refreshListener()
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(provider.lastUser?.contains("Dana:") == true)
        XCTAssertFalse(provider.lastUser?.contains("Old name") == true)
        XCTAssertFalse(session.hasUnsummarizedSpeech)
    }

    func testCompletedSummaryRebuildsFromNewAttributionWithAutoOff() async {
        let provider = RecordingProvider(deltas: ["Old name agreed to Friday."])
        let (session, store) = session(provider)
        await session.refreshListener()
        store.renameSpeaker(id: "speaker", name: "Dana")
        session.speakerAttributionsChanged()
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 2)
        XCTAssertTrue(provider.lastUser?.contains("Dana:") == true)
        XCTAssertFalse(provider.lastUser?.contains("Old name") == true)
    }

    func testAutoAllowsFirstSummaryAfterAttribution() async {
        let provider = RecordingProvider(deltas: ["Summary"])
        let (session, _) = session(provider)
        session.autoSummaryEnabled = true
        session.speakerAttributionsChanged()
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(session.listenerSummary, "Summary")
    }

    func testSecondAttributionWhileRebuildingKeepsExistingSummaryIntent() async {
        let (session, store) = session(RecordingProvider(deltas: ["Original summary"]))
        await session.refreshListener()
        let held = HeldSpeakerSummaryProvider()
        session.providers[.listener] = held
        store.renameSpeaker(id: "speaker", name: "Dana")
        session.speakerAttributionsChanged()
        for _ in 0..<1_000 {
            if held.requestCount == 1 { break }
            await Task.yield()
        }
        XCTAssertEqual(held.requestCount, 1)
        store.renameSpeaker(id: "speaker", name: "Alex")
        session.speakerAttributionsChanged()
        for _ in 0..<1_000 {
            if held.requestCount == 2 { break }
            await Task.yield()
        }
        XCTAssertEqual(held.requestCount, 2)
        XCTAssertTrue(held.lastUser?.contains("Alex:") == true)
        held.finish("Alex agreed to Friday.")
        await session.waitForResponse(.listener)
        XCTAssertEqual(session.listenerSummary, "Alex agreed to Friday.")
        XCTAssertFalse(session.speakerSummaryNeedsRebuild)
    }

    func testResetDoesNotCarryRebuildIntentIntoNewConversation() async {
        let provider = RecordingProvider(deltas: ["Original summary"])
        let (session, _) = session(provider)
        await session.refreshListener()
        session.aiEnabled = false
        session.speakerAttributionsChanged()
        XCTAssertTrue(session.speakerSummaryNeedsRebuild)
        session.resetConversation()
        session.aiEnabled = true
        session.store.apply(TranscriptSegment(source: .others, text: "A new conversation.", isFinal: true, start: 0, end: 1))
        session.speakerAttributionsChanged()
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertFalse(session.speakerSummaryNeedsRebuild)
    }

    func testRejectedResetKeepsActiveConversationRebuildIntent() async throws {
        let (session, _) = session(RecordingProvider(deltas: ["Original summary"]))
        await session.refreshListener()
        session.aiEnabled = false
        session.speakerAttributionsChanged()
        try await session.start()
        session.resetConversation()
        XCTAssertTrue(session.speakerSummaryNeedsRebuild)
        await session.stop()
    }

    func testAIBeingOffPreventsReplacementRequest() async {
        let provider = RecordingProvider(deltas: ["Summary"])
        let (session, _) = session(provider)
        await session.refreshListener()
        session.aiEnabled = false
        session.speakerAttributionsChanged()
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(session.listenerSummary.isEmpty)
        XCTAssertTrue(session.hasUnsummarizedSpeech)
    }

    func testInFlightFirstSummaryCannotRestoreOldLabelsAfterAttribution() async {
        let provider = HeldSpeakerSummaryProvider()
        let (session, store) = session(provider)
        let refresh = Task { await session.refreshListener() }
        for _ in 0..<1_000 {
            if provider.requestCount == 1 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.requestCount, 1)
        store.renameSpeaker(id: "speaker", name: "Dana")
        session.speakerAttributionsChanged()
        // This provider deliberately does not stop producing when the consumer is cancelled.
        provider.finish("Old name agreed to Friday.")
        await refresh.value
        await session.waitForResponse(.listener)
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(session.listenerSummary.isEmpty)
        XCTAssertTrue(session.hasUnsummarizedSpeech)
        XCTAssertFalse(session.streamingRoles.contains(.listener))
    }
}

private final class HeldSpeakerSummaryProvider: LLMProvider, @unchecked Sendable {
    let id = "held-speaker-summary"
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var count = 0
    private var user: String?
    var requestCount: Int { lock.withLock { count } }
    var lastUser: String? { lock.withLock { user } }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation; count += 1; user = request.messages.last?.content }
        }
    }

    func finish(_ text: String) {
        let target = lock.withLock { continuation }
        target?.yield(text)
        target?.finish()
    }
}
