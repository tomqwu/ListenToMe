import XCTest
@testable import ListenToMeCore

@MainActor
final class SharedQuickLoopTests: XCTestCase {
    private let publish = """
    {"action":"publish","context":"Monday, Sarah","bullets":["Sarah confirms Monday."],
    "reviews":[{"mode":"summary","confidence":"high","reason":"New delivery decision"}]}
    """
    private let keep = #"{"action":"keep","context":"Monday, Sarah","bullets":[],"reviews":[]}"#

    func testQuickRequestUsesIdenticalGenerationControlsAcrossApps() throws {
        let batch = try XCTUnwrap(QuickSummaryContext().batch([.init(id: "a", text: "A decision")], summary: ""))
        XCTAssertEqual(batch.request.purpose, .quickEvaluation)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: OllamaProvider.requestBody(
            model: "flash", request: batch.request, options: .init(thinking: true, maximumTokens: 9000))) as? [String: Any])
        XCTAssertEqual(body["think"] as? Bool, false)
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["num_predict"] as? Int, 3072)
        XCTAssertEqual(options["temperature"] as? Int, 0)
    }

    func testLongPlanningPreambleNeedsCompleteFinalDecisionAndNeverReachesDisplay() async throws {
        let request = try QuickSummaryContext.manualRequest(source: "Sarah confirms Monday.")
        let planning = String(repeating: "Internal planning. ", count: 420)
        let result = try await QuickSummaryReader.evaluate(request,
            provider: MockLLMProvider(id: "flash", deltas: [planning, publish]))
        XCTAssertEqual(result.summary, "- Sarah confirms Monday.")
        do {
            _ = try await QuickSummaryReader.evaluate(request,
                provider: MockLLMProvider(id: "flash", deltas: [planning, String(publish.dropLast(10))]))
            XCTFail("A token-truncated final decision must not publish planning or partial JSON")
        } catch { XCTAssertTrue(error is QuickSummaryError) }
    }

    func testMacEventLoopRoutesRecommendationsToFullModelsAndDoesNotPoll() async throws {
        for name in ["ollama-cloud", "ollama-local"] {
            let provider = MockLLMProvider(id: name, deltas: [publish])
            let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
                makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                makeProvider: { model in
                    model == name ? provider : MockLLMProvider(id: model, deltas: ["Full review from " + model])
                }, models: [.quick: name, .listener: name + "-summary", .deep: name + "-deep"],
                autoInterval: .milliseconds(15))
            try await session.start()
            let speech = TranscriptSegment(source: .others, text: "Sarah confirms Monday.", isFinal: true, start: 0, end: 1)
            await session.ingest(speech)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(session.quickReader.completedReads, 0, "Automation requires opt-in")
            session.autoSummaryEnabled = true
            for _ in 0..<100 where session.quickReader.completedReads == 0 { try await Task.sleep(for: .milliseconds(5)) }
            XCTAssertEqual(session.quickSuggestion, "- Sarah confirms Monday.", name)
            for _ in 0..<100 where session.automaticReviews.completedCounts[.summary] == nil {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertEqual(session.listenerSummary, "Full review from " + name + "-summary")
            XCTAssertTrue(session.deepAnswer.isEmpty)
            let count = session.quickReader.completedReads
            await session.ingest(speech)
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertEqual(session.quickReader.completedReads, count, "Duplicate/idle events cannot poll")
            session.notes = "Changed notes"
            session.stop()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(session.quickReader.completedReads, count, "Stop cancels pending evaluation")
        }
    }

    func testMacAutomaticReviewsCarryAttributionNotesAndUserDirectives() async throws {
        let quick = MockLLMProvider(id: "quick", deltas: [publish])
        let reviews = CapturingReviewProvider()
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { model -> any LLMProvider in model == "quick" ? quick : reviews },
            models: [.quick: "quick", .listener: "summary-model", .deep: "deep-model"],
            autoInterval: .milliseconds(15))
        session.responseLanguage = "Simplified Chinese"
        session.personaGuidance = "Act as the hiring manager."
        session.referenceContext = "SPEC: rollout gates"
        try await session.start()
        session.notes = "Ask about budget"
        session.autoSummaryEnabled = true
        await session.ingest(.init(source: .others, text: "Can you own the rollout?", isFinal: true,
                                   start: 0, end: 1, speakerName: "Alice"))
        await session.ingest(.init(source: .you, text: "Yes, by Friday.", isFinal: true, start: 1, end: 2))
        for _ in 0..<200 where session.automaticReviews.completedCounts[.summary] == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        let captured = await reviews.requests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertTrue(request.system.contains("Simplified Chinese"), request.system)
        XCTAssertTrue(request.system.contains("Act as the hiring manager."), request.system)
        let source = request.messages[0].content
        XCTAssertTrue(source.contains("Alice: Can you own the rollout?"), source)
        XCTAssertTrue(source.contains("You: Yes, by Friday."), source)
        XCTAssertTrue(source.contains("Notes: Ask about budget"), source)
        session.stop()
    }

    /// #115: the automatic recap and a manual Quick answer are two different things. The recap must
    /// never replace an answer the user just asked for, and the evaluator must be grounded in the
    /// recap, never in the answer.
    func testAutomaticRecapNeitherReplacesNorGroundsOnAFreshManualQuickAnswer() async throws {
        let second = """
        {"action":"publish","context":"Monday, Sarah, Tuesday review","bullets":["Review moves to Tuesday."],"reviews":[]}
        """
        let quick = QuickPaneTestProvider(evaluations: [publish, second], answer: "Draft: Hi Sarah, Monday works.")
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in quick }, models: [.quick: "quick"], autoInterval: .milliseconds(15))
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(.init(source: .others, text: "Sarah confirms Monday.", isFinal: true, start: 0, end: 1))
        for _ in 0..<200 where session.quickReader.completedReads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickRecap, "- Sarah confirms Monday.")
        XCTAssertEqual(session.quickSuggestion, session.quickRecap)

        await session.respondQuick(.draftReply)
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah, Monday works.")
        XCTAssertEqual(session.quickRecap, "- Sarah confirms Monday.", "A manual answer is not the recap")

        await session.ingest(.init(source: .others, text: "The review moves to Tuesday.", isFinal: true, start: 2, end: 3))
        for _ in 0..<200 where session.quickReader.completedReads < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah, Monday works.",
                       "A fresh manual answer must survive the next automatic recap")
        XCTAssertEqual(session.quickRecap, "- Review moves to Tuesday.")
        XCTAssertTrue(session.quickAnswerOverridesRecap)
        XCTAssertEqual(session.autoQuickStatus, "Recap updated · Showing your generated answer")
        let visible = await quick.visibleSummaries()
        XCTAssertEqual(visible.last, "- Sarah confirms Monday.",
                       "The evaluator is grounded in the recap, never in the manual answer")
        XCTAssertFalse(visible.contains { $0.contains("Draft:") })

        session.dismissQuickAnswer()
        XCTAssertEqual(session.quickSuggestion, "- Review moves to Tuesday.")
        XCTAssertFalse(session.quickAnswerOverridesRecap)
        session.stop()
    }

    func testAManualAnswerStopsProtectingThePaneOnceItIsNoLongerFresh() {
        var answer = ManualQuickAnswer()
        XCTAssertFalse(answer.isFresh(at: 1_000), "No answer has been generated yet")
        answer.completed(at: 1_000)
        XCTAssertTrue(answer.isFresh(at: 1_000 + ManualQuickAnswer.freshness - 1))
        XCTAssertFalse(answer.isFresh(at: 1_000 + ManualQuickAnswer.freshness),
                       "After the freshness window the recap owns the pane again")
        answer.completed(at: 1_000)
        answer.dismiss()
        XCTAssertFalse(answer.isFresh(at: 1_000))
    }

    /// An expired manual answer must not strand a newer recap: the recap is applied on the next
    /// automatic evaluation, and "Show recap" stays available the whole time in between.
    func testAnExpiredManualAnswerReleasesThePaneToTheNextAutomaticRecap() async throws {
        let second = """
        {"action":"publish","context":"Monday, Sarah, Tuesday review","bullets":["Review moves to Tuesday."],"reviews":[]}
        """
        let third = """
        {"action":"publish","context":"Monday, Sarah, Tuesday, Friday","bullets":["Sign-off moves to Friday."],"reviews":[]}
        """
        let quick = QuickPaneTestProvider(evaluations: [publish, second, third], answer: "Draft: Hi Sarah, Monday works.")
        let time = TestClock(seconds: 1_000)
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in quick }, models: [.quick: "quick"], autoInterval: .milliseconds(15),
            clock: { time.seconds })
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(.init(source: .others, text: "Sarah confirms Monday.", isFinal: true, start: 0, end: 1))
        for _ in 0..<200 where session.quickReader.completedReads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        await session.respondQuick(.draftReply)
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah, Monday works.")

        await session.ingest(.init(source: .others, text: "The review moves to Tuesday.", isFinal: true, start: 2, end: 3))
        for _ in 0..<200 where session.quickReader.completedReads < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah, Monday works.", "Still fresh")
        XCTAssertTrue(session.quickAnswerOverridesRecap, "Show recap must be offered while a newer recap waits")

        time.seconds += ManualQuickAnswer.freshness
        XCTAssertTrue(session.quickAnswerOverridesRecap,
                      "An expired answer still hides the recap, so the way back must stay visible")
        await session.ingest(.init(source: .others, text: "Sign-off moves to Friday.", isFinal: true, start: 4, end: 5))
        for _ in 0..<200 where session.quickReader.completedReads < 3 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickSuggestion, "- Sign-off moves to Friday.",
                       "Once the window elapses the recap owns the pane again")
        XCTAssertFalse(session.quickAnswerOverridesRecap)
        session.stop()
    }

    /// A half-streamed manual answer is not an answer the user can swap away from: offering
    /// "Show recap" mid-stream would splice the recap and the still-appending draft tail.
    func testTheRecapIsNotOfferedWhileAManualQuickAnswerIsStillStreaming() async throws {
        let quick = HeldAnswerProvider(evaluations: [publish])
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in quick }, models: [.quick: "quick"], autoInterval: .milliseconds(15))
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(.init(source: .others, text: "Sarah confirms Monday.", isFinal: true, start: 0, end: 1))
        for _ in 0..<200 where session.quickReader.completedReads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickRecap, "- Sarah confirms Monday.")

        let answer = Task { await session.respondQuick(.draftReply) }
        for _ in 0..<200 where !(await quick.isStreamingAnswer()) { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah,", "The answer is only half streamed")
        XCTAssertFalse(session.quickAnswerOverridesRecap, "Show recap must not appear mid-stream")
        XCTAssertNotEqual(session.autoQuickStatus, "Recap updated · Showing your generated answer")
        session.dismissQuickAnswer()
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah,",
                       "Dismissing mid-stream must not splice the recap into the streaming answer")

        let finished = await quick.finishAnswer()
        XCTAssertTrue(finished)
        await answer.value
        XCTAssertEqual(session.quickSuggestion, "Draft: Hi Sarah, Monday works.")
        XCTAssertTrue(session.quickAnswerOverridesRecap, "A finished answer can be swapped for the recap")
        XCTAssertEqual(session.autoQuickStatus, "Recap updated · Showing your generated answer")
        session.dismissQuickAnswer()
        XCTAssertEqual(session.quickSuggestion, "- Sarah confirms Monday.")
        session.stop()
    }

    /// #111 follow-up: a review that survives a notes keystroke must also *count* as that review, or
    /// the recommendation stays outstanding and the identical model call runs again.
    func testAReviewCompletingAcrossANotesEditIsMarkedReviewedAndNotRepeated() async throws {
        let decision = """
        {"action":"publish","context":"Azure latency","bullets":["Azure latency is the topic."],
        "reviews":[{"mode":"summary","confidence":"high","reason":"New topic"}]}
        """
        let quick = MockLLMProvider(id: "quick", deltas: [decision])
        let reviews = HeldReviewProvider()
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { model -> any LLMProvider in model == "quick" ? quick : reviews },
            models: [.quick: "quick", .listener: "summary-model"], autoInterval: .milliseconds(15))
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(.init(source: .others, text: "Why is Azure slow today?", isFinal: true, start: 0, end: 1))
        for _ in 0..<200 where session.automaticReviews.activeMode != .summary { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.automaticReviews.activeMode, .summary)
        // Type into Notes while the review is in flight: it must neither cancel nor un-count it.
        session.notes = "Ask about the budget"
        XCTAssertEqual(session.automaticReviews.activeMode, .summary, "A notes keystroke must not cancel it")
        let released = await reviews.release()
        XCTAssertTrue(released)
        for _ in 0..<200 where session.automaticReviews.completedCounts[.summary] == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(session.listenerSummary, "Full review")
        XCTAssertTrue(session.quickReader.reviewsCompleted.contains("summary"),
                      "A review that finished across a notes edit still satisfies the recommendation")
        XCTAssertFalse(session.quickReader.recommendations.contains { $0.mode == "summary" })
        try await Task.sleep(for: .milliseconds(80))
        let count = await reviews.requestCount()
        XCTAssertEqual(count, 1, "The identical review must not run twice because notes changed")
        session.stop()
    }

    func testMacLiveSpeechTriggersWithoutFinalEventAndSilenceDoesNotPoll() async throws {
        let provider = MockLLMProvider(id: "live", deltas: [publish])
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.quick: "live"], autoInterval: .milliseconds(15))
        try await session.start()
        session.autoSummaryEnabled = true
        await session.ingest(.init(source: .others, text: "Sarah confirms delivery on Monday.", isFinal: false, start: 0, end: 2))
        for _ in 0..<100 where session.quickReader.completedReads == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickSuggestion, "- Sarah confirms Monday.")
        XCTAssertTrue(session.store.utterances.isEmpty)
        let count = session.quickReader.completedReads
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(session.quickReader.completedReads, count)
        session.stop()
    }

    func testReaderKeepsOutputRejectsMalformedAndRetriesUnreadChanges() async throws {
        let reader = QuickSummaryReader()
        let pieces = [QuickSummaryContext.Piece(id: "s1", text: "Sarah confirms Monday.")]
        let batch = try XCTUnwrap(reader.context.batch(pieces, summary: "Existing"))
        var output = "Existing"
        await reader.read(batch, provider: MockLLMProvider(id: "bad", deltas: ["not JSON"]), isCurrent: { true }, apply: { output = $0 })
        XCTAssertEqual(output, "Existing"); XCTAssertEqual(reader.failures, 1)
        XCTAssertTrue(reader.context.hasChanges(pieces))
        await reader.read(batch, provider: MockLLMProvider(id: "good", deltas: [publish]), isCurrent: { true }, apply: { output = $0 })
        XCTAssertEqual(output, "- Sarah confirms Monday."); XCTAssertEqual(reader.failures, 0)
        reader.markReviewed("summary"); XCTAssertTrue(reader.recommendations.isEmpty)
        let next = try XCTUnwrap(reader.context.batch(pieces + [.init(id: "s2", text: "Yes, Monday.")], summary: output))
        await reader.read(next, provider: MockLLMProvider(id: "keep", deltas: [keep]), isCurrent: { true }, apply: { output = $0 })
        XCTAssertTrue(reader.unchanged); XCTAssertEqual(output, "- Sarah confirms Monday.")
        reader.clearError(); reader.reset(); XCTAssertEqual(reader.completedReads, 0)
    }

    func testBacklogPublishesFirstUsefulResultBeforeAllBatchesFinish() async throws {
        let reader = QuickSummaryReader()
        let pieces = (0..<12).map { QuickSummaryContext.Piece(id: "s\($0)", text: String(repeating: "Meeting detail. ", count: 40)) }
        let batch = try XCTUnwrap(reader.context.batch(pieces, summary: ""))
        XCTAssertTrue(batch.hasMore)
        var output = ""
        await reader.read(batch, provider: MockLLMProvider(id: "first", deltas: [publish]),
                          isCurrent: { true }, apply: { output = $0 })
        XCTAssertEqual(output, "- Sarah confirms Monday.", "Do not hide a successful recap behind the remaining backlog")
        XCTAssertTrue(reader.context.hasChanges(pieces), "Remaining speech must still be evaluated")
        XCTAssertTrue(reader.recommendations.isEmpty, "Full review suggestions wait for the complete context")
    }

    func testNetworkFailureKeepsSummaryAndUnreadInputUntilRetrySucceeds() async throws {
        for (code, message) in [(URLError.networkConnectionLost, "internet connection was lost"),
                                (.notConnectedToInternet, "offline"), (.timedOut, "timed out")] {
            let reader = QuickSummaryReader()
            let pieces = [QuickSummaryContext.Piece(id: "decision", text: "Sarah confirms Monday.")]
            let batch = try XCTUnwrap(reader.context.batch(pieces, summary: "Existing summary"))
            var output = "Existing summary"
            await reader.read(batch, provider: NetworkFailureProvider(code: code), isCurrent: { true }, apply: { output = $0 })
            XCTAssertTrue(reader.error?.contains(message) == true)
            XCTAssertEqual(output, "Existing summary")
            XCTAssertTrue(reader.context.hasChanges(pieces))
            XCTAssertFalse(reader.isReading)
            await reader.read(batch, provider: MockLLMProvider(id: "retry", deltas: [publish]),
                              isCurrent: { true }, apply: { output = $0 })
            XCTAssertNil(reader.error)
            XCTAssertEqual(output, "- Sarah confirms Monday.")
            XCTAssertFalse(reader.context.hasChanges(pieces))
        }
    }

    func testUnavailableProviderPausesWithoutChangingSelection() async throws {
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { MockLLMProvider(id: $0, deltas: []) }, models: [.quick: "apple-intelligence"],
            autoInterval: .milliseconds(10), providerAvailability: { _ in "Model unavailable" })
        session.notes = "Decision"; session.autoSummaryEnabled = true
        try await session.start(); try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(session.autoQuickStatus.contains("Auto paused"))
        XCTAssertEqual(session.models[.quick], "apple-intelligence")
        XCTAssertEqual(session.quickReader.completedReads, 0)
        session.stop()
    }
}

private struct NetworkFailureProvider: LLMProvider {
    let id = "network-failure"
    let code: URLError.Code
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: URLError(code)) }
    }
}

/// Records every full-review request the automatic coordinator dispatches.
/// Answers Quick evaluations with prepared decisions and every other request with a manual answer,
/// recording the `visibleSummary` each evaluation was grounded in.
/// A mutable wall clock for the session's injected `clock`, readable from its `@Sendable` closure.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval
    init(seconds: TimeInterval) { value = seconds }
    var seconds: TimeInterval {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// Evaluates Quick normally, but streams a manual answer in two deltas and holds the second until
/// the test releases it, so the pane can be inspected mid-stream.
private actor HeldAnswerProvider: LLMProvider {
    nonisolated let id = "held-answer"
    private var evaluations: [String]
    private var held: AsyncThrowingStream<String, Error>.Continuation?
    init(evaluations: [String]) { self.evaluations = evaluations }
    func isStreamingAnswer() -> Bool { held != nil }
    func finishAnswer() -> Bool {
        guard let held else { return false }
        held.yield(" Monday works."); held.finish(); self.held = nil
        return true
    }
    private func respond(_ request: LLMRequest, _ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        guard request.purpose == .quickEvaluation else {
            continuation.yield("Draft: Hi Sarah,"); held = continuation; return
        }
        continuation.yield(evaluations.count > 1 ? evaluations.removeFirst() : (evaluations.first ?? ""))
        continuation.finish()
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await self.respond(request, continuation) } }
    }
}

private actor QuickPaneTestProvider: LLMProvider {
    nonisolated let id = "quick-pane"
    private var evaluations: [String]
    private let answer: String
    private var grounding: [String] = []
    init(evaluations: [String], answer: String) { self.evaluations = evaluations; self.answer = answer }
    func visibleSummaries() -> [String] { grounding }
    private func next(_ request: LLMRequest) -> String {
        guard request.purpose == .quickEvaluation else { return answer }
        if let data = request.messages[0].content.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            grounding.append(object["visibleSummary"] as? String ?? "")
        }
        return evaluations.count > 1 ? evaluations.removeFirst() : (evaluations.first ?? "")
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(await self.next(request))
                continuation.finish()
            }
        }
    }
}

/// Holds one review request open so a test can change the session while it is in flight.
private actor HeldReviewProvider: LLMProvider {
    nonisolated let id = "held-review"
    private var held: AsyncThrowingStream<String, Error>.Continuation?
    private var requests = 0
    func requestCount() -> Int { requests }
    func release() -> Bool {
        guard let held else { return false }
        held.yield("Full review"); held.finish(); self.held = nil
        return true
    }
    private func hold(_ continuation: AsyncThrowingStream<String, Error>.Continuation) {
        requests += 1; held = continuation
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in Task { await self.hold(continuation) } }
    }
}

private actor CapturingReviewProvider: LLMProvider {
    nonisolated let id = "capturing-review"
    private var captured: [LLMRequest] = []
    func requests() -> [LLMRequest] { captured }
    private func record(_ request: LLMRequest) { captured.append(request) }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.record(request)
                continuation.yield("Full review")
                continuation.finish()
            }
        }
    }
}
