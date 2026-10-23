import XCTest
@testable import ListenToMeCore

/// The cloud AI preset catalog (issue #214): each vendor's address, headers, key binding and request
/// shape, checked against a stubbed URLProtocol. No network, no real keys.
final class CloudAIPresetTests: XCTestCase {
    private let key = "sk-synthetic-preset-key"

    override func tearDown() {
        OpenAIStubProtocol.reset()
        AnthropicFallbackSupport.shared.reset()
        super.tearDown()
    }

    func testCatalogAddressesAndLinks() {
        let expected: [CloudAIPreset.ID: (base: String, chat: String, models: String)] = [
            .openAI: ("https://api.openai.com/v1", "https://api.openai.com/v1/chat/completions",
                      "https://api.openai.com/v1/models"),
            .anthropic: ("https://api.anthropic.com/v1", "https://api.anthropic.com/v1/messages",
                         "https://api.anthropic.com/v1/models"),
            .gemini: ("https://generativelanguage.googleapis.com/v1beta/openai",
                      "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                      "https://generativelanguage.googleapis.com/v1beta/openai/models"),
            .deepSeek: ("https://api.deepseek.com", "https://api.deepseek.com/chat/completions",
                        "https://api.deepseek.com/models"),
            .openRouter: ("https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1/chat/completions",
                          "https://openrouter.ai/api/v1/models"),
            .groq: ("https://api.groq.com/openai/v1", "https://api.groq.com/openai/v1/chat/completions",
                    "https://api.groq.com/openai/v1/models"),
            .mistral: ("https://api.mistral.ai/v1", "https://api.mistral.ai/v1/chat/completions",
                       "https://api.mistral.ai/v1/models"),
            .xAI: ("https://api.x.ai/v1", "https://api.x.ai/v1/chat/completions", "https://api.x.ai/v1/models")
        ]
        XCTAssertEqual(CloudAIPreset.all.map(\.id), CloudAIPreset.ID.allCases, "One preset per vendor, in menu order")
        for preset in CloudAIPreset.all {
            let urls = try? XCTUnwrap(expected[preset.id])
            XCTAssertEqual(preset.baseURL.absoluteString, urls?.base, preset.name)
            XCTAssertEqual(preset.chatURL.absoluteString, urls?.chat, preset.name)
            XCTAssertEqual(preset.modelsURL.absoluteString, urls?.models, preset.name)
            for link in [preset.baseURL, preset.keyPageURL, preset.privacyPolicyURL] {
                XCTAssertEqual(link.scheme, "https", "\(preset.name): \(link)")
            }
            XCTAssertEqual(preset.disclosure, "Sends your transcript to \(preset.vendor)")
            XCTAssertEqual(OpenAICompatibleEndpoint.reach(of: preset.baseURL), .internet, "Never called local")
            XCTAssertEqual(CloudAIPreset.preset(preset.id), preset)
        }
        XCTAssertEqual(CloudAIPreset.preset(.anthropic).highlightedModel, "claude-opus-5-5")
        XCTAssertEqual(CloudAIPreset.preset(.anthropic).suggestedModels,
                       ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
    }

    func testEachVendorHasItsOwnKeychainItemBoundToItsOwnOrigin() {
        let accounts = CloudAIPreset.all.map(\.keychainAccount)
        XCTAssertEqual(Set(accounts).count, accounts.count)
        XCTAssertFalse(accounts.contains("ollama"))
        XCTAssertFalse(accounts.contains("openai-compatible"), "Never the custom server's key")
        let origins = CloudAIPreset.all.map(\.origin)
        XCTAssertEqual(Set(origins).count, origins.count, "No two vendors share an origin, so no key can cross")
        XCTAssertEqual(CloudAIPreset.preset(.openRouter).origin, "https://openrouter.ai:443")
    }

    func testHeadersCarryTheKeyInTheVendorsOwnField() {
        let claude = CloudAIPreset.preset(.anthropic).headers(apiKey: key)
        XCTAssertEqual(claude, ["x-api-key": key, "anthropic-version": "2026-10-21"])
        let router = CloudAIPreset.preset(.openRouter).headers(apiKey: key)
        XCTAssertEqual(router["Authorization"], "Bearer \(key)")
        XCTAssertEqual(router["HTTP-Referer"], "https://github.com/tomqwu/ListenToMe")
        XCTAssertEqual(router["X-Title"], "ListenToMe")
        for preset in CloudAIPreset.all where preset.id != .anthropic && preset.id != .openRouter {
            XCTAssertEqual(preset.headers(apiKey: key), ["Authorization": "Bearer \(key)"], preset.name)
        }
    }

    func testEveryOpenAICompatiblePresetSendsToItsOwnAddressWithItsOwnHeaders() async throws {
        for preset in CloudAIPreset.all where preset.transport != .anthropic {
            OpenAIStubProtocol.reset()
            OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([chunk("OK"), chunk(finish: "stop"), "data: [DONE]", ""])
            let provider = preset.provider(model: "m", apiKey: key, urlSession: OpenAIStubProtocol.session())
            var answer = ""
            for try await delta in provider.stream(LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")])) {
                answer += delta
            }
            XCTAssertEqual(answer, "OK", preset.name)
            let sent = try XCTUnwrap(OpenAIStubProtocol.received.first).request
            XCTAssertEqual(sent.url, preset.chatURL, preset.name)
            XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)", preset.name)
            XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Title"), preset.id == .openRouter ? "ListenToMe" : nil)
        }
    }

    func testTheClaudePresetUsesTheNativeProvider() {
        let provider = CloudAIPreset.preset(.anthropic).provider(model: "claude-opus-5-5", apiKey: key)
        XCTAssertTrue(provider is AnthropicProvider)
        XCTAssertTrue(CloudAIPreset.preset(.groq).provider(model: "m", apiKey: key) is OpenAICompatibleProvider)
    }

    // MARK: Vendor request shapes

    private func body(_ id: CloudAIPreset.ID, purpose: LLMRequest.Purpose,
                      options: OpenAICompatibleProvider.Options = .init(maximumTokens: 900)) throws -> [String: Any] {
        guard case .openAICompatible(let dialect) = CloudAIPreset.preset(id).transport else { throw XCTSkip("native") }
        let data = OpenAICompatibleProvider.requestBody(
            model: "m", request: LLMRequest(system: "s", messages: [], purpose: purpose), options: options, dialect: dialect)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testOpenAIGetsMaxCompletionTokensAndNoTemperature() throws {
        let quick = try body(.openAI, purpose: .quickEvaluation)
        XCTAssertEqual(quick["max_completion_tokens"] as? Int, 3_072)
        XCTAssertNil(quick["max_tokens"])
        XCTAssertNil(quick["temperature"], "GPT-5 reasoning models accept only the default temperature")
        XCTAssertEqual(quick["reasoning_effort"] as? String, "none")
        XCTAssertNil(quick["chat_template_kwargs"], "OpenAI rejects unknown fields")
        let chat = try body(.openAI, purpose: .chat)
        XCTAssertEqual(chat["max_completion_tokens"] as? Int, 900)
        XCTAssertNil(chat["reasoning_effort"])
    }

    func testEachVendorGetsItsOwnQuickReasoningHint() throws {
        XCTAssertEqual(try body(.deepSeek, purpose: .quickEvaluation)["thinking"] as? [String: String], ["type": "disabled"])
        XCTAssertEqual(try body(.openRouter, purpose: .quickEvaluation)["reasoning"] as? [String: String], ["effort": "none"])
        XCTAssertEqual(try body(.gemini, purpose: .quickEvaluation)["reasoning_effort"] as? String, "none")
        XCTAssertEqual(try body(.groq, purpose: .quickEvaluation)["reasoning_effort"] as? String, "none")
        for id in [CloudAIPreset.ID.mistral, .xAI] {
            let quick = try body(id, purpose: .quickEvaluation)
            XCTAssertEqual(Set(quick.keys), ["model", "messages", "stream", "temperature", "max_tokens"], id.rawValue)
        }
        let generic = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenAICompatibleProvider.requestBody(
            model: "m", request: LLMRequest(system: "s", messages: [], purpose: .quickEvaluation))) as? [String: Any])
        XCTAssertEqual(generic["reasoning_effort"] as? String, "none", "The custom server keeps #52's hints")
        XCTAssertNotNil(generic["chat_template_kwargs"])
    }

    func testAVendorThatRejectsTheHintIsAskedOnceWithoutIt() async throws {
        OpenAIStubProtocol.reply = { request in
            if OpenAIStubProtocol.received.count == 1 {
                return .response(status: 400, headers: [:], body: Data(#"{"error":{"message":"Unsupported value: 'none'"}}"#.utf8))
            }
            return OpenAIStubProtocol.sse([chunk("{}"), chunk(finish: "stop"), "data: [DONE]", ""])(request)
        }
        let provider = CloudAIPreset.preset(.openAI).provider(model: "gpt", apiKey: key, urlSession: OpenAIStubProtocol.session())
        for try await _ in provider.stream(LLMRequest(system: "s", messages: [], purpose: .quickEvaluation)) {}
        XCTAssertEqual(OpenAIStubProtocol.received.count, 2)
        let retried = try XCTUnwrap(JSONSerialization.jsonObject(with: OpenAIStubProtocol.received[1].body) as? [String: Any])
        XCTAssertNil(retried["reasoning_effort"])
        XCTAssertNil(retried["temperature"])
    }

    func testDeepSeekReasoningContentIsCarriedAsThinking() async throws {
        OpenAIStubProtocol.reply = OpenAIStubProtocol.sse([
            chunk(reasoning: "considering"), chunk("Answer"), chunk(finish: "stop"), "data: [DONE]", ""
        ])
        let provider = CloudAIPreset.preset(.deepSeek).provider(model: "deepseek-v4-pro", apiKey: key,
                                                                urlSession: OpenAIStubProtocol.session())
        var events: [LLMStreamEvent] = []
        for try await event in provider.streamEvents(LLMRequest(system: "s", messages: [])) { events.append(event) }
        XCTAssertEqual(events, [.thinking("considering"), .content("Answer")])
    }

    func testGeminiErrorArraysAreReadAndTheKeyMasked() async {
        OpenAIStubProtocol.reply = { _ in .response(status: 400, headers: ["Content-Type": "application/json"], body: Data(
            #"[{"error":{"code":400,"message":"Please pass a valid API key","status":"INVALID_ARGUMENT"}}]"#.utf8)) }
        let provider = CloudAIPreset.preset(.gemini).provider(model: "gemini", apiKey: key, urlSession: OpenAIStubProtocol.session())
        do {
            for try await _ in provider.stream(LLMRequest(system: "s", messages: [])) {}
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .http(status: 400, detail: "Please pass a valid API key"))
        }
    }

    // MARK: Model lists

    func testClaudeModelListUsesTheNativeHeadersAndOnePage() async throws {
        let list = #"{"data":[{"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5"},"#
            + #"{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"}],"has_more":false}"#
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(list.utf8))
        }
        let models = try await CloudAICatalog(session: OpenAIStubProtocol.session()).fetch(.preset(.anthropic), apiKey: key)
        XCTAssertEqual(models, ["claude-opus-5-5", "claude-sonnet-5-5"])
        let sent = try XCTUnwrap(OpenAIStubProtocol.received.first).request
        XCTAssertEqual(sent.url?.absoluteString, "https://api.anthropic.com/v1/models?limit=1000")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), key)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(CloudAIPreset.preset(.anthropic).suggestions(in: models), ["claude-opus-5-5", "claude-sonnet-5-5"],
                       "Only suggestions the vendor lists are highlighted")
    }

    func testGeminiModelPrefixIsStrippedAndOpenRouterGetsAttribution() async throws {
        OpenAIStubProtocol.reply = { _ in .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(
            #"{"object":"list","data":[{"id":"models/gemini-3.8-flash"},{"id":"gemini-3.8-flash"},{"id":"models/gemini-3.8-pro"}]}"#.utf8)) }
        let gemini = try await CloudAICatalog(session: OpenAIStubProtocol.session()).fetch(.preset(.gemini), apiKey: key)
        XCTAssertEqual(gemini, ["gemini-3.8-flash", "gemini-3.8-pro"])
        OpenAIStubProtocol.received = []
        _ = try await CloudAICatalog(session: OpenAIStubProtocol.session()).fetch(.preset(.openRouter), apiKey: key)
        let sent = try XCTUnwrap(OpenAIStubProtocol.received.first).request
        XCTAssertEqual(sent.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "HTTP-Referer"), "https://github.com/tomqwu/ListenToMe")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
    }

    func testModelListErrorsMaskTheKeyAndRedirectsAreRefused() async {
        OpenAIStubProtocol.reply = { _ in .response(status: 401, headers: [:], body: Data(
            #"{"type":"error","error":{"type":"authentication_error","message":"bad key sk-synthetic-preset-key"}}"#.utf8)) }
        do {
            _ = try await CloudAICatalog(session: OpenAIStubProtocol.session()).fetch(.preset(.anthropic), apiKey: key)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AnthropicError, .invalidKey(status: 401, detail: "bad key [API key]"))
        }
        OpenAIStubProtocol.reply = { _ in .redirect(status: 302, location: "https://elsewhere.example/models") }
        do {
            _ = try await CloudAICatalog(session: OpenAIStubProtocol.session()).fetch(.preset(.mistral), apiKey: key)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .redirected(status: 302, location: "elsewhere.example"))
        }
    }
}
