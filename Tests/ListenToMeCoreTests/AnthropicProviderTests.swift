import XCTest
@testable import ListenToMeCore

/// Contract tests for `AnthropicProvider` against a stubbed URLProtocol (issue #214): the native
/// Messages API request shape, the event stream, stop reasons and HTTP errors. No network.
final class AnthropicProviderTests: XCTestCase {
    private let key = "sk-ant-synthetic-0000"

    override func tearDown() {
        OpenAIStubProtocol.reset()
        AnthropicFallbackSupport.shared.reset()
        super.tearDown()
    }

    private func provider(_ model: String = "claude-opus-5-5", maximumBytes: Int = 1 << 24) -> AnthropicProvider {
        AnthropicProvider(model: model, apiKey: key, urlSession: OpenAIStubProtocol.session(),
                          maximumResponseBytes: maximumBytes, sleep: { _ in })
    }

    private func request(_ purpose: LLMRequest.Purpose = .chat) -> LLMRequest {
        LLMRequest(system: "sys", messages: [ChatMessage(role: "user", content: "hello")], purpose: purpose)
    }

    private func text(_ provider: AnthropicProvider, _ request: LLMRequest? = nil) async throws -> String {
        var text = ""
        for try await delta in provider.stream(request ?? self.request()) { text += delta }
        return text
    }

    private func failure(_ provider: AnthropicProvider, _ request: LLMRequest? = nil) async -> Error? {
        do { _ = try await text(provider, request); return nil } catch { return error }
    }

    private func sentBody(_ index: Int = 0) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: OpenAIStubProtocol.received[index].body) as? [String: Any])
    }

    // MARK: Request shape

    func testPostsTheNativeMessagesShapeWithoutSamplingParameters() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream(["Hel", "lo"]))
        let answer = try await text(provider())
        XCTAssertEqual(answer, "Hello")
        let sent = try XCTUnwrap(OpenAIStubProtocol.received.first).request
        XCTAssertEqual(sent.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), key)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"), "The key travels only in x-api-key")
        XCTAssertFalse(sent.httpShouldHandleCookies)
        let body = try sentBody()
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["system"] as? String, "sys")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 32_000)
        XCTAssertEqual(body["messages"] as? [[String: String]], [["role": "user", "content": "hello"]])
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
        for rejected in ["temperature", "top_p", "top_k", "thinking"] {
            XCTAssertNil(body[rejected], "\(rejected) is never sent on API version 2026-10-21")
        }
    }

    func testOpusAndSonnetOptIntoServerSideFallbacksButHaikuDoesNot() async throws {
        for (model, expected) in [("claude-opus-5-5", true), ("claude-sonnet-5-5", true), ("claude-haiku-5-5", false)] {
            OpenAIStubProtocol.reset()
            OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream(["OK"]))
            _ = try await text(provider(model))
            let sent = try XCTUnwrap(OpenAIStubProtocol.received.first).request
            XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-beta"),
                           expected ? "server-side-fallback-2026-07-01" : nil, model)
            XCTAssertEqual(try sentBody()["fallbacks"] as? String, expected ? "default" : nil, model)
        }
    }

    func testAModelThatRejectsFallbacksIsAskedOnceWithoutThemAndNotOfferedThemAgain() async throws {
        OpenAIStubProtocol.reply = { request in
            let beta = request.value(forHTTPHeaderField: "anthropic-beta")
            if beta != nil {
                return .response(status: 400, headers: ["Content-Type": "application/json"], body: Data(
                    #"{"type":"error","error":{"type":"invalid_request_error","message":"fallbacks: not supported for this model"}}"#.utf8))
            }
            return OpenAIStubProtocol.sse(claudeStream(["OK"]))(request)
        }
        let answer = try await text(provider("claude-sonnet-5-5"))
        XCTAssertEqual(answer, "OK")
        XCTAssertEqual(OpenAIStubProtocol.received.count, 2)
        XCTAssertNil(try sentBody(1)["fallbacks"])
        _ = try await text(provider("claude-sonnet-5-5"))
        XCTAssertEqual(OpenAIStubProtocol.received.count, 3, "The rejection is remembered for this model")
        XCTAssertNil(OpenAIStubProtocol.received[2].request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testQuickEvaluatorUsesLowEffortAndStructuredOutputWithoutPrefill() async throws {
        let decision = #"{"action":"publish","context":"Launch moves to Friday.","bullets":["Launch moves to Friday."],"reviews":[]}"#
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream([decision]))
        let quick = try QuickSummaryContext.manualRequest(source: "You: Let's move the launch to Friday.")
        let result = try await QuickSummaryReader.evaluate(quick, provider: provider())
        XCTAssertEqual(result.bullets, ["Launch moves to Friday."])
        let body = try sentBody()
        XCTAssertEqual(body["max_tokens"] as? Int, AnthropicProvider.quickMaximumTokens)
        let config = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(config["effort"] as? String, "low")
        let format = try XCTUnwrap(config["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), ["action", "context", "bullets", "reviews"])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual((body["messages"] as? [[String: String]])?.last?["role"], "user", "Never an assistant prefill")
        XCTAssertNil(body["temperature"])
    }

    func testMessagesAreFoldedIntoAlternatingTurnsThatStartAndEndWithTheUser() {
        let folded = AnthropicProvider.messages([
            ChatMessage(role: "assistant", content: "stray"), ChatMessage(role: "user", content: "a"),
            ChatMessage(role: "system", content: "b"), ChatMessage(role: "assistant", content: "c"),
            ChatMessage(role: "user", content: "d"), ChatMessage(role: "assistant", content: "prefill")
        ])
        XCTAssertEqual(folded, [["role": "user", "content": "a\n\nb"], ["role": "assistant", "content": "c"],
                                ["role": "user", "content": "d"]])
        XCTAssertEqual(AnthropicProvider.messages([]), [["role": "user", "content": "(empty)"]])
    }

    // MARK: Event stream

    func testThinkingDeltasPingsAndUnknownEventsAreIgnored() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            "event: message_start", #"data: {"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5"}}"#, "",
            "event: ping", #"data: {"type":"ping"}"#, "",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"secret plan"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"abc"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"fallback"}}"#,
            #"data: {"type":"brand_new_event"}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Answer"}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}"#,
            #"data: {"type":"message_stop"}"#, ""
        ])
        var events: [LLMStreamEvent] = []
        for try await event in provider().streamEvents(request()) { events.append(event) }
        XCTAssertEqual(events, [.content("Answer")], "Thinking is never shown or saved")
    }

    func testAnErrorEventFailsTheRequest() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            #"data: {"type":"message_start","message":{}}"#,
            "event: error", #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#, ""
        ])
        let error = await failure(provider())
        XCTAssertEqual(error as? AnthropicError, .stream(type: "overloaded_error", message: "Overloaded"))
        XCTAssertTrue(error?.localizedDescription.contains("overloaded") == true)
    }

    func testARefusalFailsWithAClearMessage() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            #"data: {"type":"message_start","message":{}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"cyber"}}}"#,
            #"data: {"type":"message_stop"}"#, ""
        ])
        let error = await failure(provider())
        XCTAssertEqual(error as? AnthropicError, .refused(category: "cyber"))
        XCTAssertTrue(error?.localizedDescription.contains("declined") == true)
    }

    func testMaxTokensKeepsThePartialTextAndReportsTheCutOff() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream(["Partial"], stopReason: "max_tokens"))
        var received = ""
        do {
            for try await delta in provider().stream(request()) { received += delta }
            XCTFail("A cut-off answer is never reported as complete")
        } catch {
            XCTAssertEqual(error as? AnthropicError, .cutOff)
            XCTAssertTrue(error.localizedDescription.contains("cut off"))
        }
        XCTAssertEqual(received, "Partial")
    }

    func testAStreamWithoutMessageStopIsIncomplete() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(Array(claudeStream(["Half an ans"]).dropLast(2)))
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .incomplete)
    }

    func testThinkingOnlyAndEmptyAnswersFailTheContract() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, #"data: {"type":"message_stop"}"#, ""
        ])
        let thinking = await failure(provider())
        XCTAssertEqual(thinking as? OpenAICompatibleError, .thinkingOnly)
        XCTAssertTrue(OpenAICompatibleContractLedger.isContractFailure(thinking!))
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream(["  "]))
        let empty = await failure(provider())
        XCTAssertEqual(empty as? OpenAICompatibleError, .empty)
    }

    func testCRLFFramingIsAccepted() async throws {
        let body = Data(claudeStream(["Hi"]).joined(separator: "\r\n").utf8)
        OpenAIStubProtocol.reply = { _ in .response(status: 200, headers: ["Content-Type": "text/event-stream"], body: body) }
        let answer = try await text(provider())
        XCTAssertEqual(answer, "Hi")
    }

    func testAPageThatIsNotAnEventStreamFails() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(["<html>Sign in to Wi-Fi</html>"], contentType: "text/html")
        let error = await failure(provider())
        XCTAssertEqual(error as? AnthropicError, .notEventStream(contentType: "text/html"))
    }

    func testAJSONErrorBodyOnASuccessfulStatusFails() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(
            [#"{"type":"error","error":{"type":"api_error","message":"boom"}}"#], contentType: "application/json")
        let error = await failure(provider())
        XCTAssertEqual(error as? AnthropicError, .stream(type: "api_error", message: "boom"))
    }

    func testOversizedResponsesAreStopped() async {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse(claudeStream([String(repeating: "x", count: 4_000)]))
        let error = await failure(provider(maximumBytes: 1_000))
        XCTAssertEqual(error as? OpenAICompatibleError, .tooLarge)
    }

    // MARK: HTTP errors

    func testABadKeyIsNamedAndNeverEchoed() async {
        OpenAIStubProtocol.reply = { _ in .response(status: 401, headers: ["Content-Type": "application/json"], body: Data(
            #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key sk-ant-synthetic-0000"}}"#.utf8)) }
        let error = await failure(provider())
        guard case .invalidKey(401, let detail)? = error as? AnthropicError else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(detail, "invalid x-api-key [API key]")
        XCTAssertFalse(error!.localizedDescription.contains(key))
    }

    func testAnInvalidRequestShowsAnthropicsMessageWithTheKeyMasked() async {
        OpenAIStubProtocol.reply = { _ in .response(status: 400, headers: [:], body: Data(
            #"{"type":"error","error":{"type":"invalid_request_error","message":"model: bad for sk-ant-synthetic-0000"}}"#.utf8)) }
        let error = await failure(provider("claude-haiku-5-5"))
        XCTAssertEqual(error as? AnthropicError, .invalidRequest("model: bad for [API key]"))
        XCTAssertEqual(OpenAIStubProtocol.received.count, 1)
    }

    func testOverloadIsRetriedOnceWhenRetryAfterIsShort() async throws {
        var attempts = 0
        OpenAIStubProtocol.reply = { request in
            attempts += 1
            if attempts == 1 { return .response(status: 529, headers: ["retry-after": "2"], body: Data()) }
            return OpenAIStubProtocol.sse(claudeStream(["OK"]))(request)
        }
        let answer = try await text(provider())
        XCTAssertEqual(answer, "OK")
        XCTAssertEqual(OpenAIStubProtocol.received.count, 2)
    }

    func testOverloadFailsAfterOneRetryAndALongRetryAfterIsNotWaitedFor() async {
        OpenAIStubProtocol.reply = { _ in .response(status: 429, headers: ["retry-after": "0"], body: Data()) }
        let twice = await failure(provider())
        XCTAssertEqual(twice as? AnthropicError, .overloaded(status: 429, retryAfter: 0, detail: nil))
        XCTAssertEqual(OpenAIStubProtocol.received.count, 2, "At most one retry")
        OpenAIStubProtocol.reset()
        OpenAIStubProtocol.reply = { _ in .response(status: 529, headers: ["retry-after": "600"], body: Data()) }
        let long = await failure(provider())
        XCTAssertEqual(long as? AnthropicError, .overloaded(status: 529, retryAfter: 600, detail: nil))
        XCTAssertEqual(OpenAIStubProtocol.received.count, 1)
        XCTAssertTrue(long?.localizedDescription.contains("overloaded") == true)
    }

    func testRedirectsAreRefused() async {
        OpenAIStubProtocol.reply = { _ in .redirect(status: 307, location: "https://evil.example/v1/messages") }
        let error = await failure(provider())
        XCTAssertEqual(error as? OpenAICompatibleError, .redirected(status: 307, location: "evil.example"))
        XCTAssertEqual(OpenAIStubProtocol.received.count, 1, "The redirect is never followed")
    }

    func testRetryAfterParsing() {
        XCTAssertEqual(AnthropicTransport.retryAfter("3"), 3)
        XCTAssertEqual(AnthropicTransport.retryAfter("1.2"), 2)
        XCTAssertNil(AnthropicTransport.retryAfter("Wed, 21 Oct 2026 07:28:00 GMT"))
        XCTAssertNil(AnthropicTransport.retryAfter(nil))
    }

    func testEveryErrorHasAMessage() {
        let errors: [AnthropicError] = [
            .invalidKey(status: 403, detail: nil), .overloaded(status: 429, retryAfter: nil, detail: "slow"),
            .invalidRequest("x"), .http(status: 500, detail: nil), .stream(type: "api_error", message: nil),
            .refused(category: nil), .cutOff, .notEventStream(contentType: nil)
        ]
        for error in errors { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
}

/// A complete Messages API stream that answers with `texts`.
func claudeStream(_ texts: [String], stopReason: String = "end_turn") -> [String] {
    func data(_ object: [String: Any]) -> String {
        "data: " + String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(),
                          as: UTF8.self)
    }
    var lines = ["event: message_start", data(["type": "message_start", "message": ["id": "msg_1"]]), "",
                 data(["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]])]
    for text in texts {
        lines.append(data(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]]))
    }
    lines += [data(["type": "content_block_stop", "index": 0]),
              data(["type": "message_delta", "delta": ["stop_reason": stopReason]]),
              "event: message_stop", data(["type": "message_stop"]), ""]
    return lines
}
