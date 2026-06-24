import XCTest
@testable import ListenToMeCore

/// Real end-to-end contract test against a live Ollama server. SKIPPED unless `LTM_E2E=1`, so
/// normal `swift test` / CI never hit the network. Run via `make e2e`. Env overrides:
/// `LTM_E2E_MODEL` (default llama3.1), `LTM_E2E_BASEURL` (e.g. https://ollama.com for Ollama Cloud),
/// `LTM_E2E_KEY` (Ollama Cloud API key, sent as a Bearer token).
final class OllamaContractE2ETests: XCTestCase {
    func testRealOllamaStreamingProducesContent() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["LTM_E2E"] == "1",
            "e2e only: set LTM_E2E=1 and run a local Ollama (use `make e2e`)"
        )
        let model = env["LTM_E2E_MODEL"] ?? "llama3.1"
        let key = (env["LTM_E2E_KEY"]?.isEmpty == false) ? env["LTM_E2E_KEY"] : nil
        let provider: OllamaProvider
        if let base = env["LTM_E2E_BASEURL"], let url = URL(string: base) {
            provider = OllamaProvider(model: model, baseURL: url, apiKey: key)
        } else {
            provider = OllamaProvider(model: model)   // live init -> http://localhost:11434
        }
        let request = PromptBuilder.build(
            context: PromptContext(
                messages: [
                    TranscriptSegment(source: .others, text: "Can you ship by Friday?",
                                      isFinal: true, start: 0, end: 1)
                ],
                notes: nil
            ),
            action: .answerQuestion
        )
        var content = ""
        for try await delta in provider.stream(request) {
            content += delta
        }
        XCTAssertFalse(
            content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "expected non-empty streamed content from \(model)"
        )
    }
}
