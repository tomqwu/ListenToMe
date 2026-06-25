import XCTest
@testable import ListenToMeCore

@MainActor
final class MeetingSessionTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        now: @escaping @Sendable () -> TimeInterval = { 0 },
        listenerDebounce: TimeInterval = 0
    ) -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: listenerDebounce,
            clock: now
        )
        return (session, store)
    }

    // MARK: - CopilotRole

    func testCopilotRoleHasThreeCases() {
        XCTAssertEqual(CopilotRole.allCases.count, 3)
        XCTAssertTrue(CopilotRole.allCases.contains(.listener))
        XCTAssertTrue(CopilotRole.allCases.contains(.quick))
        XCTAssertTrue(CopilotRole.allCases.contains(.deep))
    }

    func testRecapGetsLargerTranscriptBudgetThanOtherActions() {
        XCTAssertGreaterThan(MeetingSession.transcriptBudget(for: .recap),
                             MeetingSession.transcriptBudget(for: .answerQuestion))
        XCTAssertEqual(MeetingSession.transcriptBudget(for: .answerQuestion),
                       MeetingSession.transcriptBudget(for: .followUp))
        XCTAssertEqual(MeetingSession.transcriptBudget(for: .proactive),
                       MeetingSession.transcriptBudget(for: .answerQuestion))
    }

    // MARK: - Initial state

    func testInitialStateHasCorrectDefaults() {
        let (session, _) = makeSession()
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.listenerSummary, "")
        XCTAssertEqual(session.quickSuggestion, "")
        XCTAssertEqual(session.deepAnswer, "")
        XCTAssertTrue(session.streamingRoles.isEmpty)
        XCTAssertTrue(session.proactiveEnabled)
        XCTAssertEqual(session.models[.listener], "L")
        XCTAssertEqual(session.models[.quick], "Q")
        XCTAssertEqual(session.models[.deep], "D")
    }

    // MARK: - respondQuick

    func testRespondQuickStreamsIntoQuickSuggestion() async {
        let (session, _) = makeSession()
        await session.respondQuick(.answerQuestion)
        XCTAssertEqual(session.quickSuggestion, "[Q]")
    }

    func testRespondQuickClearsStreamingRoleAfterCompletion() async {
        let (session, _) = makeSession()
        await session.respondQuick(.answerQuestion)
        XCTAssertFalse(session.streamingRoles.contains(.quick))
    }

    func testRespondQuickDoesNotAffectDeepAnswer() async {
        let (session, _) = makeSession()
        await session.respondQuick(.answerQuestion)
        XCTAssertEqual(session.deepAnswer, "")
    }

    func testRespondQuickDoesNotAffectListenerSummary() async {
        let (session, _) = makeSession()
        await session.respondQuick(.answerQuestion)
        XCTAssertEqual(session.listenerSummary, "")
    }

    // MARK: - respondDeep

    func testRespondDeepStreamsIntoDeepAnswer() async {
        let (session, _) = makeSession()
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.deepAnswer, "[D]")
    }

    func testRespondDeepClearsStreamingRoleAfterCompletion() async {
        let (session, _) = makeSession()
        await session.respondDeep(.answerQuestion)
        XCTAssertFalse(session.streamingRoles.contains(.deep))
    }

    func testRespondDeepDoesNotAffectQuickSuggestion() async {
        let (session, _) = makeSession()
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.quickSuggestion, "")
    }

    // MARK: - refreshListener

    func testRefreshListenerStreamsIntoListenerSummary() async {
        let (session, _) = makeSession()
        await session.refreshListener()
        XCTAssertEqual(session.listenerSummary, "[L]")
    }

    func testRefreshListenerClearsStreamingRoleAfterCompletion() async {
        let (session, _) = makeSession()
        await session.refreshListener()
        XCTAssertFalse(session.streamingRoles.contains(.listener))
    }

    func testRefreshListenerDoesNotAffectQuickOrDeep() async {
        let (session, _) = makeSession()
        await session.refreshListener()
        XCTAssertEqual(session.quickSuggestion, "")
        XCTAssertEqual(session.deepAnswer, "")
    }

    // MARK: - setModel

    func testSetModelUpdatesModelsDict() {
        let (session, _) = makeSession()
        session.setModel(.quick, "Q2")
        XCTAssertEqual(session.models[.quick], "Q2")
    }

    func testSetModelChangesProviderForSubsequentRequests() async {
        let (session, _) = makeSession()
        session.setModel(.quick, "Q2")
        await session.respondQuick(.answerQuestion)
        XCTAssertEqual(session.quickSuggestion, "[Q2]")
    }

    func testSetModelListenerChangesListenerProvider() async {
        let (session, _) = makeSession()
        session.setModel(.listener, "L2")
        await session.refreshListener()
        XCTAssertEqual(session.listenerSummary, "[L2]")
    }

    func testSetModelDeepChangesDeepProvider() async {
        let (session, _) = makeSession()
        session.setModel(.deep, "D2")
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.deepAnswer, "[D2]")
    }

    // MARK: - ingest → store

    func testIngestAppendsToStore() async {
        let (session, store) = makeSession()
        await session.ingest(TranscriptSegment(source: .others, text: "Hello",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(store.utterances.map(\.text), ["Hello"])
    }

    // MARK: - Proactive (quick role)

    func testIngestFiresProactiveQuickOnRemoteQuestion() async throws {
        let (session, _) = makeSession(now: { 999_999 })
        try await session.start()
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        await session.waitForResponse(.quick)
        XCTAssertEqual(session.quickSuggestion, "[Q]")
        session.stop()
    }

    func testIngestDoesNotFireProactiveWhenDisabled() async throws {
        let (session, _) = makeSession(now: { 999_999 })
        try await session.start()
        session.proactiveEnabled = false
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.quickSuggestion, "")
        session.stop()
    }

    func testIngestIgnoresOwnSpeechForProactive() async throws {
        let (session, _) = makeSession(now: { 999_999 })
        try await session.start()
        await session.ingest(TranscriptSegment(source: .you, text: "What should I do?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.quickSuggestion, "")
        session.stop()
    }

    func testIngestDoesNotFireProactiveWhenNotRunning() async {
        let (session, _) = makeSession(now: { 999_999 })
        // session never started
        await session.ingest(TranscriptSegment(source: .others, text: "Are we ready?",
                                               isFinal: true, start: 0, end: 1))
        XCTAssertEqual(session.quickSuggestion, "")
    }

    // MARK: - Listener debounce via ingest

    func testIngestFinalSegmentTriggersListenerRefreshAfterDebounce() async throws {
        let (session, _) = makeSession(now: { 999_999 }, listenerDebounce: 0)
        try await session.start()
        await session.ingest(TranscriptSegment(source: .you, text: "Here is my update.",
                                               isFinal: true, start: 0, end: 1))
        // Yield to let the background listener Task register in responseTasks, then await it.
        for _ in 0 ..< 10 { await Task.yield() }
        await session.waitForResponse(.listener)
        XCTAssertEqual(session.listenerSummary, "[L]")
        session.stop()
    }

    func testIngestNonFinalSegmentDoesNotTriggerListenerRefresh() async throws {
        let (session, _) = makeSession(now: { 999_999 }, listenerDebounce: 0)
        try await session.start()
        await session.ingest(TranscriptSegment(source: .you, text: "Still speaking...",
                                               isFinal: false, start: 0, end: 1))
        // Give a moment to see if listener fires
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(session.listenerSummary, "")
        session.stop()
    }

    // MARK: - waitForResponse role-specific

    func testWaitForResponseListenerAwaitsListenerTask() async {
        let (session, _) = makeSession()
        await session.refreshListener()
        await session.waitForResponse(.listener)
        XCTAssertEqual(session.listenerSummary, "[L]")
    }

    func testWaitForResponseQuickAwaitsQuickTask() async {
        let (session, _) = makeSession()
        await session.respondQuick(.answerQuestion)
        await session.waitForResponse(.quick)
        XCTAssertEqual(session.quickSuggestion, "[Q]")
    }

    func testWaitForResponseDeepAwaitsDeepTask() async {
        let (session, _) = makeSession()
        await session.respondDeep(.answerQuestion)
        await session.waitForResponse(.deep)
        XCTAssertEqual(session.deepAnswer, "[D]")
    }

    // MARK: - Roles stream independently

    func testRolesStreamIntoSeparateOutputProperties() async {
        let (session, _) = makeSession()
        await session.respondQuick(.answerQuestion)
        await session.respondDeep(.answerQuestion)
        await session.refreshListener()
        XCTAssertEqual(session.quickSuggestion, "[Q]")
        XCTAssertEqual(session.deepAnswer, "[D]")
        XCTAssertEqual(session.listenerSummary, "[L]")
    }

    // MARK: - stop

    func testStopSetsIsRunningFalse() async throws {
        let (session, _) = makeSession()
        try await session.start()
        session.stop()
        XCTAssertFalse(session.isRunning)
    }

    func testStopIsIdempotent() async throws {
        let (session, _) = makeSession()
        try await session.start()
        session.stop()
        session.stop()
        XCTAssertFalse(session.isRunning)
    }
}
