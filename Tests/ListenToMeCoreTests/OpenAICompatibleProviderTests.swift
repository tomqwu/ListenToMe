import XCTest
@testable import ListenToMeCore

/// Contract tests for `OpenAICompatibleProvider` against a stubbed URLProtocol (issue #52): the same
/// stream validation, error and termination rules the Ollama path enforces, plus redirect, cookie
/// and credential handling.
final class OpenAICompatibleProviderTests: XCTestCase {
    private let base = URL(string: "http://studio.local:1234/v1")!

    override func tearDown() {
        OpenAIStubProtocol.reset()
        super.tearDown()
    }

    private func provider(key: String? = nil, maximumBytes: Int = OpenAICompatibleProvider.defaultMaximumResponseBytes,
                          options: OpenAICompatibleProvider.Options = .init()) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(model: "qwen3-8b", baseURL: base, apiKey: key, urlSession: OpenAIStubProtocol.session(),
                                 options: options, maximumResponseBytes: maximumBytes)
    }

    private func request(_ purpose: LLMRequest.Purpose = .chat) -> LLMRequest {
        LLMRequest(system: "sys", messages: [ChatMessage(role: "user", content: "hello")], purpose: purpose)
    }

    private func collect(_ provider: OpenAICompatibleProvider,
                         _ request: LLMRequest? = nil) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in provider.streamEvents(request ?? self.request()) { events.append(event) }
        return events
    }

    private func failure(_ provider: OpenAICompatibleProvider) async -> Error? {
        do {
            for try await _ in provider.stream(request()) {}
            return nil
        } catch { return error }
    }

    // MARK: Success paths

    func testStreamsContentAndReasoningSeparatelyAndPostsTheOpenAIShape() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            ": OPENROUTER PROCESSING", "", "event: message",
            chunk(reasoning: "Let me think"), chunk("Hel"), chunk("lo"), chunk(finish: "stop"), "data: [DONE]", ""
        ])
        let events = try await collect(provider(key: "sk-test-1234"))
        XCTAssertEqual(events, [.thinking("Let me think"), .content("Hel"), .content("lo")])
        let sent = try XCTUnwrap(OpenAIStubProtocol.received.first)
        XCTAssertEqual(sent.request.url?.absoluteString, "http://studio.local:1234/v1/chat/completions")
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-1234")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertFalse(sent.request.httpShouldHandleCookies, "Cookies are never stored or sent")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3-8b")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["temperature"], "Chat requests keep the server's defaults")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "system", "content": "sys"], ["role": "user", "content": "hello"]])
    }

    func testNoAuthorizationHeaderWithoutAKey() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("OK"), "data: [DONE]"])
        _ = try await collect(provider(key: ""))
        XCTAssertNil(OpenAIStubProtocol.received.first?.request.value(forHTTPHeaderField: "Authorization"))
    }

    func testQuickEvaluationGetsTheSameControlsAsOllama() throws {
        let quick = OpenAICompatibleProvider.requestBody(model: "m", request: request(.quickEvaluation),
                                                         options: .init(temperature: 0.7, maximumTokens: 50))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: quick) as? [String: Any])
        XCTAssertEqual(object["temperature"] as? Double, 0)
        XCTAssertEqual(object["max_tokens"] as? Int, 3_072)
        let chat = OpenAICompatibleProvider.requestBody(model: "m", request: request(),
                                                        options: .init(temperature: 0.2, maximumTokens: 700))
        let chatObject = try XCTUnwrap(JSONSerialization.jsonObject(with: chat) as? [String: Any])
        XCTAssertEqual(chatObject["temperature"] as? Double, 0.2)
        XCTAssertEqual(chatObject["max_tokens"] as? Int, 700)
    }

    func testAFinishReasonWithoutDoneStillCompletes() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("Done."), chunk(finish: "stop")])
        let events = try await collect(provider())
        XCTAssertEqual(events, [.content("Done.")])
    }

    func testCarriageReturnLineEndingsAreAccepted() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("A") + "\r", "\r", "data: [DONE]\r"])
        let events = try await collect(provider())
        XCTAssertEqual(events, [.content("A")])
    }

    func testANonStreamedJSONCompletionIsAccepted() async throws {
        let body = #"{"choices":[{"message":{"role":"assistant","content":"Whole answer","reasoning_content":"hm"}}]}"#
        OpenAIStubProtocol.reply = { _ in .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8)) }
        let events = try await collect(provider())
        XCTAssertEqual(events, [.thinking("hm"), .content("Whole answer")])
    }

    // MARK: Termination and validation

    func testATruncatedStreamIsIncompleteEvenAfterContent() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("Partial "), chunk("text")])
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .incomplete)
    }

    func testAnEmptyAnswerAndAReasoningOnlyAnswerAreRejected() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("  "), "data: [DONE]"])
        var error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .empty)
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk(reasoning: "thinking"), "data: [DONE]"])
        error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .thinkingOnly)
    }

    func testAnErrorObjectInsideTheStreamFailsWithTheServersMessage() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            chunk("Half"), #"data: {"error":{"message":"Provider overloaded","code":502}}"#, "data: [DONE]"
        ])
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .server("Provider overloaded"))
        XCTAssertEqual(error?.localizedDescription, "Model error: Provider overloaded")
    }

    func testAnErrorFinishReasonFails() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("Half"), chunk(finish: "error")])
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .server("The server ended the response with an error."))
    }

    func testAnHTMLPageIsNotAnEventStream() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(["<html><body>Sign in to the Wi-Fi</body></html>"],
                                                          contentType: "text/html")
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .notEventStream(contentType: "text/html"))
        XCTAssertTrue(error?.localizedDescription.contains("text/html") == true)
    }

    func testAMalformedJSONCompletionIsRejected() async throws {
        for body in ["not json", #"{"choices":[]}"#] {
            OpenAIStubProtocol.reply = { _ in .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8)) }
            let error = await failure(provider())
            XCTAssertEqual(error as? OpenAICompatibleError, .notEventStream(contentType: "application/json"), body)
        }
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"error":"bad model"}"#.utf8))
        }
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .server("bad model"))
    }

    func testResponsesOverTheSizeLimitAreStopped() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(Array(repeating: chunk("xxxxxxxxxx"), count: 50) + ["data: [DONE]"])
        let error = await failure(provider(maximumBytes: 1_024))
        XCTAssertEqual(error as? OpenAICompatibleError, .tooLarge)
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(repeating: 0x20, count: 4_096))
        }
        let jsonError = await failure(provider(maximumBytes: 1_024))
        XCTAssertEqual(jsonError as? OpenAICompatibleError, .tooLarge)
    }

    func testASingleUnterminatedLineCannotGrowWithoutBound() async throws {
        let line = "data: " + String(repeating: "x", count: OpenAICompatibleProvider.maximumLineBytes + 10)
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([line])
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .tooLarge)
    }

    // MARK: HTTP, redirects, credentials and connectivity

    func testNon2xxResponsesSurfaceABoundedRedactedExplanation() async throws {
        let key = "sk-or-v1-secret-value"
        OpenAIStubProtocol.reply = { _ in
            .response(status: 401, headers: ["Content-Type": "application/json"],
                      body: Data(#"{"error":{"message":"Invalid key sk-or-v1-secret-value"}}"#.utf8))
        }
        let error = await failure(provider(key: key))
        let message = try XCTUnwrap(error?.localizedDescription)
        XCTAssertTrue(message.hasPrefix("HTTP 401: API key rejected"), message)
        XCTAssertTrue(message.contains("Invalid key [API key]"), message)
        XCTAssertFalse(message.contains(key), "An API key is never echoed into an error")

        OpenAIStubProtocol.reply = { _ in .response(status: 404, headers: [:], body: Data()) }
        let missing = await failure(provider())
        XCTAssertEqual(missing as? OpenAICompatibleError, .http(status: 404, detail: nil))
        XCTAssertTrue(missing?.localizedDescription.contains("/v1") == true)

        OpenAIStubProtocol.reply = { _ in .response(status: 418, headers: [:], body: Data(repeating: 0x61, count: 20_000)) }
        let teapot = await failure(provider())
        guard case .http(418, let detail?) = teapot as? OpenAICompatibleError else { return XCTFail("\(String(describing: teapot))") }
        XCTAssertEqual(detail.count, OpenAICompatibleError.maximumErrorBodyBytes)
    }

    func testStreamedServerErrorsAreRedactedToo() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([#"data: {"error":"key sk-abcdef is over quota"}"#])
        let error = await failure(provider(key: "sk-abcdef"))
        XCTAssertEqual(error as? OpenAICompatibleError, .server("key [API key] is over quota"))
    }

    func testRedirectsAreNeverFollowed() async throws {
        OpenAIStubProtocol.reply = { request in
            request.url?.host == "studio.local" ? .redirect(status: 307, location: "https://relay.example.com/v1/chat/completions")
                : .response(status: 200, headers: ["Content-Type": "text/event-stream"],
                            body: Data([chunk("leaked"), "data: [DONE]"].joined(separator: "\n").utf8))
        }
        let error = await failure(provider(key: "sk-test-1234"))
        XCTAssertEqual(error as? OpenAICompatibleError, .redirected(status: 307, location: "relay.example.com"))
        XCTAssertEqual(OpenAIStubProtocol.received.map { $0.request.url?.host }, ["studio.local"],
                       "Nothing, and no key, may reach the redirect target")
        XCTAssertTrue(error?.localizedDescription.contains("does not follow redirects") == true)
    }

    func testConnectionFailuresNameTheHostAndCancellationStaysCancellation() async throws {
        OpenAIStubProtocol.reply = { _ in .failure(.timedOut) }
        let timeout = await failure(provider())
        XCTAssertEqual(timeout as? OpenAICompatibleError,
                       .unreachable(host: "studio.local:1234", reason: "The request timed out."))
        XCTAssertTrue(timeout?.localizedDescription.hasPrefix("Could not reach studio.local:1234") == true)
        OpenAIStubProtocol.reply = { _ in .failure(.cannotConnectToHost) }
        guard case .unreachable = await failure(provider()) as? OpenAICompatibleError else { return XCTFail() }
        XCTAssertTrue(OpenAICompatibleTransport.mapped(URLError(.cancelled), host: base, apiKey: nil) is CancellationError)
    }

    func testCancellingTheConsumerStopsTheStream() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("one"), chunk("two"), "data: [DONE]"])
        let subject = provider(), prompt = request()
        let task = Task { () -> Int in
            var count = 0
            for try await _ in subject.stream(prompt) { count += 1; withUnsafeCurrentTask { $0?.cancel() } }
            return count
        }
        let result = await task.result
        if case .success(let count) = result { XCTAssertLessThanOrEqual(count, 2) }
    }

    func testErrorDescriptionsAreActionable() {
        let cases: [OpenAICompatibleError] = [
            .incomplete, .empty, .thinkingOnly, .tooLarge, .invalidModelList, .notEventStream(contentType: nil),
            .redirected(status: 302, location: nil), .http(status: 429, detail: "slow down"),
            .http(status: 503, detail: nil), .http(status: 400, detail: "context length exceeded")
        ]
        for error in cases { XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)") }
        XCTAssertEqual(OpenAICompatibleError.http(status: 400, detail: "context length exceeded").errorDescription,
                       "HTTP 400: context length exceeded")
        XCTAssertTrue(OpenAICompatibleError.http(status: 429, detail: "slow down").errorDescription?.contains("Rate limited") == true)
        XCTAssertEqual(OpenAICompatibleError.redact("abc", "ab"), "abc", "Too-short keys are not used as patterns")
    }

    func testProviderReportsItsIdentityAndNoPromptLimit() {
        let provider = provider(key: "")
        XCTAssertEqual(provider.id, "openai-compatible")
        XCTAssertEqual(provider.model, "qwen3-8b")
        XCTAssertEqual(provider.baseURL, base)
        XCTAssertNil(provider.maxPromptCharacters)
    }
}
