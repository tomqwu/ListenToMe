import XCTest
@testable import ListenToMeCore

/// Regression tests for the #213 review findings on the OpenAI-compatible route (issue #52).
final class OpenAICompatibleReviewTests: XCTestCase {
    private let base = URL(string: "http://studio.local:1234/v1")!

    override func tearDown() {
        OpenAIStubProtocol.reset()
        super.tearDown()
    }

    // MARK: 1. Never auto-assign from an OpenAI-compatible catalog; never overwrite a pin

    func testAnOpenAICompatibleCatalogIsNeverAutoAssigned() {
        let catalog = ["openai/o1-pro", "anthropic/claude-opus", "meta/llama-3.1-8b"]
        let unset = PaneModelHealing.decide(current: "", pinned: false, available: catalog,
                                            fallback: "openai/o1-pro", autoAssign: false)
        XCTAssertEqual(unset, .init(model: "", persist: false), "No pane is given a vendor the user never picked")
        let kept = PaneModelHealing.decide(current: "meta/llama-3.1-8b", pinned: false, available: catalog,
                                           fallback: nil, autoAssign: false)
        XCTAssertEqual(kept, .init(model: "meta/llama-3.1-8b", persist: false))
        let gone = PaneModelHealing.decide(current: "retired-model", pinned: false, available: catalog,
                                           fallback: nil, autoAssign: false)
        XCTAssertEqual(gone, .init(model: "", persist: false), "A missing choice is unset, not replaced")
    }

    func testAPinnedPickMissingFromTheListIsNeverOverwritten() {
        let decision = PaneModelHealing.decide(current: "qwen3:32b", pinned: true, available: ["llama3.1"],
                                               fallback: "llama3.1", autoAssign: true)
        XCTAssertEqual(decision, .init(model: "llama3.1", persist: false),
                       "The pane runs on the fallback, but the stored pin survives for when the model returns")
        XCTAssertEqual(PaneModelHealing.decide(current: "qwen3:32b", pinned: true, available: ["qwen3:32b"],
                                               fallback: "llama3.1", autoAssign: true),
                       .init(model: "qwen3:32b", persist: false))
    }

    func testUnpinnedOllamaPanesStillFollowTheRoleDefault() {
        XCTAssertEqual(PaneModelHealing.decide(current: "llama3.1", pinned: false, available: ["llama3.1", "qwen3"],
                                               fallback: "qwen3", autoAssign: true),
                       .init(model: "qwen3", persist: true))
        XCTAssertEqual(PaneModelHealing.decide(current: "llama3.1", pinned: false, available: [],
                                               fallback: nil, autoAssign: true),
                       .init(model: "llama3.1", persist: false))
    }

    // MARK: 2. Reasoning hints, the strict-server fallback, and thinking-only as a contract failure

    private func quick() -> LLMRequest {
        LLMRequest(system: "s", messages: [ChatMessage(role: "user", content: "u")], purpose: .quickEvaluation)
    }

    private func body(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheQuickEvaluatorAsksServersToSkipReasoningLikeOllamasThinkFalse() throws {
        let hinted = try body(OpenAICompatibleProvider.requestBody(model: "m", request: quick()))
        XCTAssertEqual(hinted["reasoning_effort"] as? String, "none")
        XCTAssertEqual((hinted["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"], false)
        let plain = try body(OpenAICompatibleProvider.requestBody(model: "m", request: quick(), reasoningHints: false))
        XCTAssertNil(plain["reasoning_effort"])
        XCTAssertNil(plain["chat_template_kwargs"])
        let chat = try body(OpenAICompatibleProvider.requestBody(
            model: "m", request: LLMRequest(system: "s", messages: [])))
        XCTAssertNil(chat["reasoning_effort"], "Ordinary chat keeps the server's own reasoning settings")
    }

    func testAStrictServerThatRejectsTheHintsGetsOneRetryWithout() async throws {
        OpenAIStubProtocol.reply = { request in
            let sent = OpenAIStubProtocol.received.last?.body ?? Data()
            let hinted = (try? JSONSerialization.jsonObject(with: sent) as? [String: Any])?["reasoning_effort"] != nil
            _ = request
            return hinted
                ? .response(status: 400, headers: ["Content-Type": "application/json"],
                            body: Data(#"{"error":{"message":"Unrecognized request argument: reasoning_effort"}}"#.utf8))
                : .response(status: 200, headers: ["Content-Type": "text/event-stream"],
                            body: Data([chunk("{}"), "data: [DONE]"].joined(separator: "\n").utf8))
        }
        let provider = OpenAICompatibleProvider(model: "m", baseURL: base, urlSession: OpenAIStubProtocol.session())
        var text = ""
        for try await delta in provider.stream(quick()) { text += delta }
        XCTAssertEqual(text, "{}")
        XCTAssertEqual(OpenAIStubProtocol.received.count, 2)

        // Chat requests carry no hints, so a 400 there is the server's real answer and is not retried.
        OpenAIStubProtocol.received = []
        OpenAIStubProtocol.reply = { _ in .response(status: 400, headers: [:], body: Data(#"{"error":"bad"}"#.utf8)) }
        do {
            for try await _ in provider.stream(LLMRequest(system: "s", messages: [])) {}
            XCTFail("400 must fail")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .http(status: 400, detail: "bad"))
        }
        XCTAssertEqual(OpenAIStubProtocol.received.count, 1)
    }

    func testThinkingOnlyAndEmptyAnswersCountAsContractFailuresButOutagesDoNot() {
        XCTAssertTrue(OpenAICompatibleContractLedger.isContractFailure(OpenAICompatibleError.thinkingOnly))
        XCTAssertTrue(OpenAICompatibleContractLedger.isContractFailure(OpenAICompatibleError.empty))
        XCTAssertTrue(OpenAICompatibleContractLedger.isContractFailure(QuickSummaryError.message("bad JSON")))
        XCTAssertFalse(OpenAICompatibleContractLedger.isContractFailure(OpenAICompatibleError.incomplete))
        XCTAssertFalse(OpenAICompatibleContractLedger.isContractFailure(
            OpenAICompatibleError.unreachable(host: "h", reason: "r")))
        XCTAssertFalse(OpenAICompatibleContractLedger.isContractFailure(URLError(.timedOut)))
    }

    // MARK: 3. Contract results per tested model, bounded

    func testContractResultsAreKeptPerServerAndModelAndBounded() throws {
        var ledger = OpenAICompatibleContractLedger()
        ledger.record(base, model: "b", passed: false)
        ledger.record(base, model: "a", passed: true)
        XCTAssertTrue(ledger.hasFailed(base, model: "b"), "Testing A never clears B")
        XCTAssertFalse(ledger.hasFailed(base, model: "a"))
        let other = try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1"))
        XCTAssertFalse(ledger.hasFailed(other, model: "b"), "Another server's model of that name is untested")
        ledger.record(base, model: "b", passed: true)
        XCTAssertFalse(ledger.hasFailed(base, model: "b"))
        ledger.record(base, model: "", passed: false)
        XCTAssertTrue(ledger.failures.isEmpty)
        for index in 0..<(OpenAICompatibleContractLedger.capacity + 5) { ledger.record(base, model: "m\(index)", passed: false) }
        XCTAssertEqual(ledger.failures.count, OpenAICompatibleContractLedger.capacity)
        XCTAssertFalse(ledger.hasFailed(base, model: "m0"), "The oldest result goes first")
        XCTAssertTrue(ledger.hasFailed(base, model: "m\(OpenAICompatibleContractLedger.capacity + 4)"))
        XCTAssertEqual(OpenAICompatibleContractLedger(failures: Array(repeating: "x", count: 40)).failures.count,
                       OpenAICompatibleContractLedger.capacity)
    }

    // MARK: 4. All-or-nothing settings changes

    func testSettingsChangesAreValidatedBeforeAnythingIsWritten() throws {
        let current = "https://openrouter.ai/api/v1"
        XCTAssertThrowsError(try OpenAICompatibleSettingsChange.plan(
            rawURL: "http://192.168.1.2/v1", key: "sk-1", keyEdited: true, currentBaseURL: current))
        XCTAssertThrowsError(try OpenAICompatibleSettingsChange.plan(
            rawURL: "", key: "sk-1", keyEdited: true, currentBaseURL: current)) {
            XCTAssertEqual($0 as? OpenAICompatibleEndpoint.ValidationError, .keyWithoutServer)
            XCTAssertNotNil(($0 as? LocalizedError)?.errorDescription)
        }
        XCTAssertEqual(try OpenAICompatibleSettingsChange.plan(
            rawURL: "https://openrouter.ai/api/v1/", key: "sk-old", keyEdited: false, currentBaseURL: current),
                       .init(baseURL: current, keyAction: .keep), "Same origin keeps the key")
        XCTAssertEqual(try OpenAICompatibleSettingsChange.plan(
            rawURL: "http://studio.local:1234", key: "sk-old", keyEdited: false, currentBaseURL: current),
                       .init(baseURL: "http://studio.local:1234/v1", keyAction: .remove),
                       "Another origin never inherits the key")
        XCTAssertEqual(try OpenAICompatibleSettingsChange.plan(
            rawURL: "http://studio.local:1234", key: " sk-new ", keyEdited: true, currentBaseURL: current),
                       .init(baseURL: "http://studio.local:1234/v1",
                             keyAction: .store(key: "sk-new", origin: "http://studio.local:1234")))
        XCTAssertEqual(try OpenAICompatibleSettingsChange.plan(
            rawURL: current, key: "", keyEdited: true, currentBaseURL: current),
                       .init(baseURL: current, keyAction: .remove))
        XCTAssertEqual(try OpenAICompatibleSettingsChange.plan(
            rawURL: "", key: "", keyEdited: false, currentBaseURL: ""), .init(baseURL: "", keyAction: .keep))
    }

    // MARK: 5. IPv6 by bytes

    func testIPv6IsClassifiedFromItsBytes() throws {
        let cases: [(String, OpenAICompatibleEndpoint.Reach)] = [
            ("https://[fd::1]/v1", .internet),            // 00fd::1, not fd00::/8
            ("https://[fc00::5]/v1", .privateNetwork),
            ("https://[fe90::1]/v1", .privateNetwork),    // inside fe80::/10
            ("https://[febf::1]/v1", .privateNetwork),
            ("https://[fec0::1]/v1", .internet),          // outside fe80::/10
            ("https://[0:0:0:0:0:0:0:1]/v1", .loopback),
            ("https://[::ffff:192.168.1.2]/v1", .privateNetwork),
            ("https://[::ffff:127.0.0.1]/v1", .loopback),
            ("https://[::ffff:8.8.8.8]/v1", .internet)
        ]
        for (raw, reach) in cases {
            XCTAssertEqual(OpenAICompatibleEndpoint.reach(of: try XCTUnwrap(URL(string: raw))), reach, raw)
        }
        XCTAssertTrue(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "fe90::1"))
        XCTAssertTrue(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "fe80::1%en0"))
        XCTAssertTrue(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "0:0:0:0:0:0:0:1"))
        XCTAssertTrue(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "::ffff:127.0.0.1"))
        XCTAssertFalse(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "fec0::1"))
        XCTAssertFalse(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "fd::1"))
        XCTAssertFalse(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "::ffff:192.168.1.2"))
        XCTAssertFalse(OpenAICompatibleEndpoint.allowsPlainHTTP(host: "not:an:address"))
    }

    // MARK: 6. Event-stream framing

    private func collect(_ lines: String) async throws -> String {
        OpenAIStubProtocol.reply = { _ in
            .response(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(lines.utf8))
        }
        let provider = OpenAICompatibleProvider(model: "m", baseURL: base, urlSession: OpenAIStubProtocol.session())
        var text = ""
        for try await delta in provider.stream(LLMRequest(system: "s", messages: [])) { text += delta }
        return text
    }

    func testAMultiLineDataEventIsJoinedAsTheFormatSpecifies() async throws {
        let stream = "data: {\"choices\":[{\"delta\":\ndata: {\"content\":\"Hello\"}}]}\n\n" + chunk(" world") + "\n\ndata: [DONE]\n"
        let text = try await collect(stream)
        XCTAssertEqual(text, "Hello world")
    }

    func testAMultiLineEventThatNeverFormsJSONFails() async {
        do {
            _ = try await collect("data: {\"choices\":\ndata: oops\n\ndata: [DONE]\n")
            XCTFail("Malformed data must not pass")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .notEventStream(contentType: "text/event-stream"))
        }
        do {
            _ = try await collect(chunk("partial") + "\ndata: {\"choices\":[{\"delta\":")
            XCTFail("A stream cut inside an event is incomplete")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .incomplete)
        }
        do {
            _ = try await collect("data: {\"choices\":\n<html>\n")
            XCTFail("A non-data line inside an event is not an event stream")
        } catch {
            XCTAssertEqual(error as? OpenAICompatibleError, .notEventStream(contentType: "text/event-stream"))
        }
    }

    func testBareCarriageReturnLineEndingsAreAccepted() async throws {
        let text = try await collect(chunk("A") + "\r\r" + chunk("B") + "\r" + "data: [DONE]\r")
        XCTAssertEqual(text, "AB")
    }
}
