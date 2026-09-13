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
