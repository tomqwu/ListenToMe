import XCTest
@testable import ListenToMeCore

/// Real end-to-end contract test against a live Ollama server (local, or cloud-proxied via a
/// `:cloud` model). SKIPPED unless `LTM_E2E=1`, so normal `swift test` / CI never hit the network.
/// Run via `make e2e`. Override the model with `LTM_E2E_MODEL` (default: llama3.1).
final class OllamaContractE2ETests: XCTestCase {
    func testRealOllamaStreamingProducesContent() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LTM_E2E"] == "1",
            "e2e only: set LTM_E2E=1 and run a local Ollama (use `make e2e`)"
        )
        let model = ProcessInfo.processInfo.environment["LTM_E2E_MODEL"] ?? "llama3.1"
        let provider = OllamaProvider(model: model)   // live init -> http://localhost:11434
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
