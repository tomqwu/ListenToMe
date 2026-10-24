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
            provider = OllamaProvider(model: model, localOnly: true)   // live init -> http://localhost:11434
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

extension OllamaContractE2ETests {
    func testLocalFourKDefaultExpandsAndReadsTheOpeningOfALongPrompt() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["LTM_E2E"] == "1" && env["LTM_E2E_BASEURL"] == nil,
                          "requires the local Ollama e2e run")
        let model = env["LTM_E2E_MODEL"] ?? "llama3.1"
        let alias = "listentome-context-test-" + UUID().uuidString.lowercased()
        let base = URL(string: "http://localhost:11434")!
        func send(_ path: String, _ body: [String: Any], method: String = "POST") async throws -> Data {
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.httpMethod = method; request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "OllamaE2E", code: (response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            return data
        }
        _ = try await send("api/create", ["model": alias, "from": model, "parameters": ["num_ctx": 4096], "stream": false])
        do {
            _ = try await send("api/generate", ["model": alias, "prompt": "", "stream": false])
            let (initialData, _) = try await URLSession.shared.data(from: base.appendingPathComponent("api/ps"))
            let initial = try XCTUnwrap(JSONSerialization.jsonObject(with: initialData) as? [String: Any])
            let initialModels = try XCTUnwrap(initial["models"] as? [[String: Any]])
            let initialRunner = try XCTUnwrap(initialModels.first { ($0["name"] as? String)?.hasPrefix(alias) == true })
            XCTAssertEqual(initialRunner["context_length"] as? Int, 4_096)
            let provider = OllamaProvider(model: alias, localOnly: true,
                                          options: .init(thinking: false, temperature: 0, maximumTokens: 128))
            let content = "The launch password is VIOLET.\n" + String(repeating: "Background meeting notes. ", count: 1_300)
                + "\nWhat is the launch password given in the first sentence? Answer with that word only."
            var answer = ""
            for try await delta in provider.stream(LLMRequest(system: "Answer the question using the provided text.",
                                                              messages: [.init(role: "user", content: content)])) {
                answer += delta
            }
            XCTAssertTrue(answer.uppercased().contains("VIOLET"), answer)
            let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("api/ps"))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let models = try XCTUnwrap(object["models"] as? [[String: Any]])
            let runner = try XCTUnwrap(models.first { ($0["name"] as? String)?.hasPrefix(alias) == true })
            XCTAssertGreaterThan(try XCTUnwrap(runner["context_length"] as? Int), 4_096)
        } catch {
            _ = try? await send("api/delete", ["model": alias], method: "DELETE")
            throw error
        }
        _ = try await send("api/delete", ["model": alias], method: "DELETE")
    }
}
