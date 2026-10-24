import XCTest
@testable import ListenToMeCore

/// Streams fixed events, the last of which can be the output-limit signal.
struct ScriptedEventProvider: LLMProvider {
    let id = "scripted"
    let events: [LLMStreamEvent]
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        LLMOutputLimit.textStream(streamEvents(request))
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Issue #215: a server that stops at its output-token limit produced a partial answer. Every
/// provider reports it the same way, panes keep the text and say so, and the plain-text stream
/// never passes a cut-off answer off as whole.
final class OutputLimitTests: XCTestCase {
    override func tearDown() {
        OpenAIStubProtocol.reset()
        AnthropicFallbackSupport.shared.reset()
        super.tearDown()
    }

    private let request = LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])

    private func events(_ provider: any LLMProvider) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in provider.streamEvents(request) { events.append(event) }
        return events
    }

    /// The text the plain stream delivered, and the error it ended with.
    private func text(_ provider: any LLMProvider) async -> (String, Error?) {
        var text = ""
        do {
            for try await delta in provider.stream(request) { text += delta }
            return (text, nil)
        } catch { return (text, error) }
    }

    private func openAI() -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(model: "m", baseURL: URL(string: "http://studio.local:1234/v1")!, apiKey: nil,
                                 urlSession: OpenAIStubProtocol.session())
    }

    private func ollama(_ lines: [String]) -> OllamaProvider {
        OllamaProvider(model: "m", baseURL: URL(string: "http://x")!) { _ in
            AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            }
        }
    }

    private func claude() -> AnthropicProvider {
        AnthropicProvider(model: "claude-opus-5-5", apiKey: "sk-ant-synthetic-0000",
                          urlSession: OpenAIStubProtocol.session(), maximumResponseBytes: 1 << 24, sleep: { _ in })
    }

    // MARK: - OpenAI-compatible

    func testOpenAIFinishReasonLengthEndsWithTheSignal() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("Part"), chunk("ial", finish: "length"), "data: [DONE]"])
        let received = try await events(openAI())
        XCTAssertEqual(received, [.content("Part"), .content("ial"), .outputLimitReached])
    }

    func testOpenAIFinishReasonStopHasNoSignal() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("Whole", finish: "stop"), "data: [DONE]"])
        let received = try await events(openAI())
        XCTAssertEqual(received, [.content("Whole")])
    }

    func testOpenAINonStreamedCompletionReportsLength() async throws {
        let body = #"{"choices":[{"message":{"role":"assistant","content":"Partial"},"finish_reason":"length"}]}"#
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
        }
        let received = try await events(openAI())
        XCTAssertEqual(received, [.content("Partial"), .outputLimitReached])
    }

    func testOpenAIPlainStreamKeepsTheTextThenReportsTheCutOff() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("Partial", finish: "length")])
        let (received, error) = await text(openAI())
        XCTAssertEqual(received, "Partial")
        XCTAssertEqual(error as? LLMOutputLimitError, LLMOutputLimitError())
        XCTAssertTrue(error?.localizedDescription.contains(LLMOutputLimit.notice) == true)
    }

    // MARK: - Ollama

    func testOllamaDoneReasonLengthEndsWithTheSignal() async throws {
        let provider = ollama([#"{"message":{"content":"Partial"},"done":false}"#,
                               #"{"message":{"content":""},"done":true,"done_reason":"length"}"#])
        let received = try await events(provider)
        XCTAssertEqual(received, [.content("Partial"), .outputLimitReached])
        let (text, error) = await text(provider)
        XCTAssertEqual(text, "Partial")
        XCTAssertTrue(error is LLMOutputLimitError)
    }

    func testOllamaDoneReasonStopHasNoSignal() async throws {
        let provider = ollama([#"{"message":{"content":"Whole"},"done":false}"#,
                               #"{"message":{"content":""},"done":true,"done_reason":"stop"}"#])
        let received = try await events(provider)
        XCTAssertEqual(received, [.content("Whole")])
        XCTAssertEqual(OllamaParser.doneReason(line: "not json"), nil)
    }

    /// A model that spent the whole cap on reasoning never answered; that is still the clearer error.
    func testOllamaReasoningThatHitTheCapIsReportedAsThinkingOnly() async {
        let provider = ollama([#"{"message":{"thinking":"Hmm"},"done":false}"#,
                               #"{"message":{"content":""},"done":true,"done_reason":"length"}"#])
        let (_, error) = await text(provider)
        guard case .thinkingOnly? = error as? OllamaStreamError else { return XCTFail("got \(String(describing: error))") }
    }

    // MARK: - Anthropic

    func testClaudeMaxTokensKeepsThePartialTextAndSignals() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream(["Partial"], stopReason: "max_tokens"))
        let received = try await events(claude())
        XCTAssertEqual(received, [.content("Partial"), .outputLimitReached])
    }

    func testClaudeContextWindowExceededSignalsToo() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(
            claudeStream(["Partial"], stopReason: "model_context_window_exceeded"))
        let received = try await events(claude())
        XCTAssertEqual(received, [.content("Partial"), .outputLimitReached])
    }

    func testClaudePlainStreamStillEndsWithCutOff() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream(["Partial"], stopReason: "max_tokens"))
        let (received, error) = await text(claude())
        XCTAssertEqual(received, "Partial")
        XCTAssertEqual(error as? AnthropicError, .cutOff)
    }

    // MARK: - Shared helpers

    func testCollectDropsThinkingAndRecordsTheCutOff() async throws {
        let provider = ScriptedEventProvider(events: [.thinking("t"), .content("A"), .content("B"), .outputLimitReached])
        let (text, cutOff) = try await LLMOutputLimit.collect(provider.streamEvents(request), limit: 10,
                                                              tooLarge: URLError(.dataLengthExceedsMaximum))
        XCTAssertEqual(text, "AB")
        XCTAssertTrue(cutOff)
        let whole = ScriptedEventProvider(events: [.content("A")])
        let result = try await LLMOutputLimit.collect(whole.streamEvents(request), limit: 10,
                                                      tooLarge: URLError(.dataLengthExceedsMaximum))
        XCTAssertFalse(result.cutOff)
    }

    func testCollectEnforcesItsLimit() async {
        let provider = ScriptedEventProvider(events: [.content("ABCDEF")])
        do {
            _ = try await LLMOutputLimit.collect(provider.streamEvents(request), limit: 3,
                                                 tooLarge: URLError(.dataLengthExceedsMaximum))
            XCTFail("An oversized answer is rejected")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }

    func testTheDefaultEventStreamNeverSignals() async throws {
        let received = try await events(MockLLMProvider(id: "m", deltas: ["A", "B"]))
        XCTAssertEqual(received, [.content("A"), .content("B")])
    }
}

/// The panes: the partial text stays, the notice appears, and the next complete answer clears it.
@MainActor
final class OutputLimitSessionTests: XCTestCase {
    private func session(_ provider: any LLMProvider) -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        let session = MeetingSession(
            store: store, context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider }, models: [.listener: "L", .quick: "Q", .deep: "D"], clock: { 0 })
        store.apply(TranscriptSegment(source: .others, text: "What did we decide on pricing?", isFinal: true,
                                      start: 0, end: 2))
        return (session, store)
    }

    func testACutOffDeepAnswerKeepsItsTextAndSaysSo() async {
        let (session, _) = session(ScriptedEventProvider(events: [.content("The first half"), .outputLimitReached]))
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.deepAnswer, "The first half")
        XCTAssertEqual(session.roleNotices(.deep), [LLMOutputLimit.notice])
        XCTAssertNil(session.roleError(.deep), "A cut-off answer is not a failure")
        XCTAssertTrue(session.roleNotices(.quick).isEmpty)
    }

    func testACompleteAnswerClearsTheNotice() async {
        let (session, _) = session(ScriptedEventProvider(events: [.content("Partial"), .outputLimitReached]))
        await session.respondQuick(.answerQuestion)
        XCTAssertEqual(session.roleNotices(.quick), [LLMOutputLimit.notice])
        session.providers[.quick] = ScriptedEventProvider(events: [.content("Whole")])
        await session.respondQuick(.answerQuestion)
        XCTAssertTrue(session.roleNotices(.quick).isEmpty)
    }

    func testACutOffListenerRefreshSaysSo() async {
        let (session, _) = session(ScriptedEventProvider(events: [.content("Summary so"), .outputLimitReached]))
        await session.refreshListener()
        XCTAssertEqual(session.listenerSummary, "Summary so")
        XCTAssertEqual(session.roleNotices(.listener), [LLMOutputLimit.notice])
    }

    func testResetClearsEveryNotice() async {
        let (session, _) = session(ScriptedEventProvider(events: [.content("Partial"), .outputLimitReached]))
        await session.respondDeep(.answerQuestion)
        session.resetConversation()
        XCTAssertTrue(session.roleNotices(.deep).isEmpty)
    }

    func testRenamingASpeakerClearsTheNotices() async {
        let (session, _) = session(ScriptedEventProvider(events: [.content("Partial"), .outputLimitReached]))
        await session.respondDeep(.answerQuestion)
        session.speakerNamesChanged()
        XCTAssertTrue(session.roleNotices(.deep).isEmpty)
        await session.waitForResponse(.listener)
    }

    func testAutomaticReviewsRecordTheirOwnCutOff() {
        let (session, _) = session(ScriptedEventProvider(events: [.content("x")]))
        session.setOutput(.deep, "Half a review")
        session.recordAutomaticReview(.deep, cutOff: true)
        XCTAssertEqual(session.roleNotices(.deep), [LLMOutputLimit.notice])
        XCTAssertEqual(session.outputLimitRoles, [.deep])
        session.setOutput(.deep, "A newer review")
        XCTAssertTrue(session.roleNotices(.deep).isEmpty, "The line belongs to the text it was recorded for")
        session.recordAutomaticReview(.deep, cutOff: false)
        XCTAssertTrue(session.roleNotices(.deep).isEmpty)
    }

    /// Review item 7: Claude hitting its cap before any answer text reports the cut-off, as it did
    /// before #215, not an empty or thinking-only answer.
    func testClaudeCutOffBeforeAnyTextIsStillTheCutOff() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream([], stopReason: "max_tokens"))
        defer { OpenAIStubProtocol.reset() }
        let provider = AnthropicProvider(model: "claude-opus-5-5", apiKey: "sk-ant-synthetic-0000",
                                         urlSession: OpenAIStubProtocol.session(), maximumResponseBytes: 1 << 24,
                                         sleep: { _ in })
        do {
            for try await _ in provider.streamEvents(LLMRequest(system: "s", messages: [])) {}
            XCTFail("No answer text is not a complete answer")
        } catch { XCTAssertEqual(error as? AnthropicError, .cutOff) }
    }

    /// Review item 6: a Quick contract probe cut off at the output limit is the model failing the
    /// contract, so Auto pauses for it instead of retrying a model that always hits the cap.
    func testAnOutputLimitIsAQuickContractFailure() {
        XCTAssertTrue(OpenAICompatibleContractLedger.isContractFailure(LLMOutputLimitError()))
        XCTAssertTrue(OpenAICompatibleContractLedger.isContractFailure(AnthropicError.cutOff))
        XCTAssertFalse(OpenAICompatibleContractLedger.isContractFailure(URLError(.timedOut)))
    }
}

/// An automatic review that stopped at the limit is still applied, and the coordinator says so.
@MainActor
final class OutputLimitReviewTests: ReviewCoordinatorTestCase {
    func testACutOffAutomaticReviewIsAppliedAndMarked() async throws {
        let runner = AutomaticReviewCoordinator(summaryInterval: .milliseconds(30), deepInterval: .milliseconds(30))
        let provider = ScriptedEventProvider(events: [.content("Half a review"), .outputLimitReached])
        var outputs: [AutomaticReviewMode: String] = [:]
        runner.synchronize(enabled: true, manualBusy: false, pieces: live("Why is Azure slow?"),
                           source: "Why is Azure slow?", provider: { _ in provider },
                           apply: { mode, text, _ in outputs[mode] = text })
        runner.offer([recommendations[1]], source: "Why is Azure slow?")
        try await wait { runner.completedCounts[.deep] == 1 }
        XCTAssertEqual(outputs[.deep], "Half a review")
        XCTAssertTrue(runner.cutOffModes.contains(.deep))
        runner.reset()
        XCTAssertTrue(runner.cutOffModes.isEmpty)
    }
}
