import XCTest
@testable import ListenToMeCore

/// Real end-to-end contract test for the OpenAI-compatible provider (issue #52). SKIPPED unless
/// `LTM_E2E=1`, so normal `swift test` / CI never touch the network. `make e2e` runs it against the
/// OpenAI-compatible API that a local Ollama serves at `http://localhost:11434/v1`. Env overrides:
/// `LTM_E2E_MODEL`, `LTM_E2E_OPENAI_BASEURL` (e.g. http://localhost:1234/v1 for LM Studio) and
/// `LTM_E2E_OPENAI_KEY` (sent as a Bearer token).
final class OpenAICompatibleContractE2ETests: XCTestCase {
    func testConfiguredSmallWindowAcceptsShortInputAndRejectsOversizedInput() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LTM_E2E"] == "1", "e2e only: set LTM_E2E=1 (use `make e2e`)")
        let base = try OpenAICompatibleEndpoint.normalize(env["LTM_E2E_OPENAI_BASEURL"] ?? "http://localhost:11434/v1")
        let provider = OpenAICompatibleProvider(model: env["LTM_E2E_MODEL"] ?? "llama3.1", baseURL: base,
                                               apiKey: env["LTM_E2E_OPENAI_KEY"],
                                               contextWindow: OpenAIContextWindow(tokens: 4_096))
        let short = LLMRequest(system: "Reply briefly.", messages: [ChatMessage(role: "user", content: "Say ready.")],
                               purpose: .quickEvaluation)
        var answer = ""
        for try await delta in provider.stream(short) { answer += delta }
        XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let large = LLMRequest(system: "Summarize.", messages: [ChatMessage(role: "user", content:
            String(repeating: "Synthetic context capacity acceptance. ", count: 1_000))])
        do {
            for try await _ in provider.stream(large) {}
            XCTFail("Oversized input must fail locally")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No text was sent"), error.localizedDescription)
        }
    }

    func testRealServerListsModelsAndStreamsACompleteAnswer() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LTM_E2E"] == "1", "e2e only: set LTM_E2E=1 (use `make e2e`)")
        let model = env["LTM_E2E_MODEL"] ?? "llama3.1"
        let base = try OpenAICompatibleEndpoint.normalize(env["LTM_E2E_OPENAI_BASEURL"] ?? "http://localhost:11434/v1")
        let key = env["LTM_E2E_OPENAI_KEY"].flatMap { $0.isEmpty ? nil : $0 }

        let models = try await OpenAICompatibleCatalog().fetch(baseURL: base, apiKey: key)
        XCTAssertTrue(models.contains(model), "\(model) is not in \(base)/models: \(models.prefix(20))")

        let provider = OpenAICompatibleProvider(model: model, baseURL: base, apiKey: key)
        let request = PromptBuilder.build(
            context: PromptContext(
                messages: [TranscriptSegment(source: .others, text: "Can you ship by Friday?",
                                             isFinal: true, start: 0, end: 1)],
                notes: nil),
            action: .answerQuestion)
        var content = ""
        for try await delta in provider.stream(request) { content += delta }
        XCTAssertFalse(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "expected non-empty streamed content from \(model) at \(base)")

        // The Quick evaluator's reasoning hints must be accepted (or retried without) and yield an
        // answer rather than reasoning only. Whether a small model holds the JSON contract is the
        // model's business; the transport's job is a complete answer.
        let quick = try QuickSummaryContext.manualRequest(source: "You: Let's move the launch to Friday.")
        var evaluation = ""
        for try await delta in provider.stream(quick) { evaluation += delta }
        XCTAssertFalse(evaluation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "expected an evaluator answer, not reasoning only, from \(model) at \(base)")
    }
}
