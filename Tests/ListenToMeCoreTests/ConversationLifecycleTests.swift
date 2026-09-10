import XCTest
@testable import ListenToMeCore

@MainActor
final class ConversationLifecycleTests: XCTestCase {
    private func makeSession(_ provider: any LLMProvider) -> MeetingSession {
        MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
                       makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                       makeProvider: { _ in provider }, models: [.listener: "m", .quick: "m", .deep: "m"])
    }

    private func segment(_ text: String, source: SpeakerSource = .others, final: Bool = true) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: final, start: 0, end: 1)
    }

    func testPartialsRemainIndependentAcrossSourcesAndFinals() {
        let store = ConversationStore()
        store.apply(segment("Remote partial", final: false))
        store.apply(segment("Mic partial", source: .you, final: false))
        XCTAssertEqual(store.partials.count, 2)
        store.apply(segment("", source: .you, final: false))
        XCTAssertNil(store.partials[.you])
        XCTAssertEqual(store.partials[.others]?.text, "Remote partial")
        store.apply(segment("Mic partial", source: .you, final: false))
        store.apply(segment("Remote final"))
        XCTAssertEqual(store.partials[.you]?.text, "Mic partial")
        XCTAssertNil(store.partials[.others])
        store.reset()
        XCTAssertTrue(store.partials.isEmpty); XCTAssertTrue(store.utterances.isEmpty)
    }

    func testNewConversationClearsAllOldContextAndOutputs() async {
        let provider = RecordingProvider(deltas: ["Earlier summary"])
        let session = makeSession(provider)
        session.notes = "Old notes"; session.referenceContext = "Old attachment"
        session.store.apply(segment("Old transcript"))
        await session.refreshListener(); await session.respondQuick(.recap); await session.respondDeep(.recap)
        session.store.apply(segment("Old partial", final: false))
        session.resetConversation()
        XCTAssertTrue(session.listenerSummary.isEmpty); XCTAssertTrue(session.quickSuggestion.isEmpty)
        XCTAssertTrue(session.deepAnswer.isEmpty); XCTAssertTrue(session.notes.isEmpty)
        XCTAssertNil(session.referenceContext); XCTAssertTrue(session.store.partials.isEmpty)
        session.store.apply(segment("Fresh transcript"))
        await session.respondQuick(.answerQuestion)
        let prompt = provider.lastUser ?? ""
        XCTAssertTrue(prompt.contains("Fresh transcript"))
        for old in ["Old transcript", "Old notes", "Old attachment", "Earlier summary"] {
            XCTAssertFalse(prompt.contains(old), old)
        }
    }

    func testResetDoesNotClearAnActiveRecording() async throws {
        let session = makeSession(MockLLMProvider(id: "m", deltas: ["ok"]))
        try await session.start()
        session.store.apply(segment("Keep"))
        session.resetConversation()
        XCTAssertEqual(session.store.utterances.count, 1)
        await session.stopAndWait()
    }

    func testAIOffBlocksAutomaticAndManualInference() async throws {
        let provider = RecordingProvider(deltas: ["Should never run"])
        let session = makeSession(provider)
        session.aiEnabled = false
        try await session.start()
        await session.ingest(segment("Can you answer?"))
        await session.refreshListener(); await session.respondQuick(.recap); await session.respondDeep(.recap)
        XCTAssertNil(provider.lastUser)
        XCTAssertEqual(session.store.utterances.count, 1)
        XCTAssertTrue(session.streamingRoles.isEmpty)
        await session.stopAndWait()
    }

    func testSummaryCarriesEarlyActionsAcrossAllTranscriptBatches() async {
        let provider = LedgerProvider()
        let session = makeSession(provider)
        session.store.apply(segment("EARLY Alice owns the rollout on Wednesday."))
        for index in 0..<60 {
            session.store.apply(segment("Minute \(index): " + String(repeating: "discussion ", count: 110)))
        }
        session.store.apply(segment("LATE Bob will approve on Friday."))
        await session.refreshListener()
        let prompts = provider.prompts
        XCTAssertGreaterThan(prompts.count, 3)
        XCTAssertTrue(prompts.first?.contains("EARLY") == true)
        XCTAssertTrue(prompts.last?.contains("LATE") == true)
        XCTAssertTrue(prompts.dropFirst().allSatisfy { $0.contains("Alice owns the rollout on Wednesday") })
        for index in 0..<60 { XCTAssertTrue(prompts.contains { $0.contains("Minute \(index):") }) }
    }

    func testFailedSummaryDoesNotAcknowledgeEvidence() async {
        let provider = RecordingProvider(deltas: ["Recovered"])
        let session = makeSession(provider)
        session.store.apply(segment("Decision to preserve"))
        session.aiEnabled = false
        await session.refreshListener()
        session.aiEnabled = true
        await session.refreshListener()
        XCTAssertTrue(provider.lastUser?.contains("Decision to preserve") == true)
    }

    func testRestoreRetainsNamesAndClearsPartials() {
        let store = ConversationStore()
        store.apply(segment("Pending", final: false))
        var saved = segment("Saved")
        saved.speakerID = "alice"; saved.speakerName = "Alice"
        store.restore([saved])
        XCTAssertEqual(store.utterances, [saved]); XCTAssertTrue(store.partials.isEmpty)
    }
}

private final class LedgerProvider: LLMProvider, @unchecked Sendable {
    let id = "ledger"
    private let lock = NSLock()
    private var requests: [String] = []
    var prompts: [String] { lock.withLock { requests } }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { requests.append(request.messages.last?.content ?? "") }
        return AsyncThrowingStream { continuation in
            continuation.yield("Alice owns the rollout on Wednesday")
            continuation.finish()
        }
    }
}
