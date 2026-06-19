import XCTest
@testable import ListenToMeCore

@MainActor
final class MeetingSessionTests: XCTestCase {
    private func makeSession(deltas: [String], now: @escaping @Sendable () -> TimeInterval = { 0 })
        -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        let router = ModelRouter(default: MockLLMProvider(id: "ollama", deltas: deltas))
        let session = MeetingSession(
            store: store,
            router: router,
            context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            clock: now
        )
        return (session, store)
    }

    func testRespondStreamsIntoSuggestion() async {
        let (session, _) = makeSession(deltas: ["Ship ", "Friday."])
        await session.respond(.answerQuestion)
        XCTAssertEqual(session.suggestion, "Ship Friday.")
        XCTAssertFalse(session.isStreaming)
    }

    func testIngestAppendsToStore() async {
        let (session, store) = makeSession(deltas: ["x"])
        await session.ingest(TranscriptSegment(source: .others, text: "Hello",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(store.utterances.map(\.text), ["Hello"])
    }

    func testIngestFiresProactiveOnRemoteQuestion() async throws {
        let (session, _) = makeSession(deltas: ["Tell ", "them yes."])
        try await session.start()
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        await session.waitForResponse()
        XCTAssertEqual(session.suggestion, "Tell them yes.")
        session.stop()
    }

    func testIngestDoesNotFireWhenProactiveDisabled() async throws {
        let (session, _) = makeSession(deltas: ["nope"])
        try await session.start()
        session.proactiveEnabled = false
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.suggestion, "")
        session.stop()
    }

    func testIngestIgnoresOwnSpeech() async throws {
        let (session, _) = makeSession(deltas: ["should not run"])
        try await session.start()
        await session.ingest(TranscriptSegment(source: .you, text: "What should I do?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.suggestion, "")
        session.stop()
    }
}
