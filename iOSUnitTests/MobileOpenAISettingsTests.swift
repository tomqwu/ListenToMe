import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// OpenAI-compatible summaries on iOS (issue #52): explicit server choice, honest labels, a key bound
/// to its server, per-role models, and Auto gated on the Quick JSON contract.
@MainActor
final class MobileOpenAISettingsTests: XCTestCase {
    private let keys = ["mobileAIProvider", "mobileOpenAIBaseURL", "mobileOpenAIKeyOrigin", "mobileOpenAICatalog",
                        "mobileOpenAIModel", "mobileOpenAIQuickModel", "mobileOpenAIDeepModel",
                        "mobileOpenAIQuickContractFailure"]
    private var saved: [String: Any] = [:]
    private var savedKey = ""

    override func setUp() async throws {
        saved = [:]
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        savedKey = try MobileKeychain.read(account: MobileKeychain.openAIAccount)
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        try MobileKeychain.save("", account: MobileKeychain.openAIAccount)
    }

    override func tearDown() async throws {
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
        try MobileKeychain.save(savedKey, account: MobileKeychain.openAIAccount)
        OpenAIModelsStub.reply = nil
    }

    func testTheProviderIsAnExplicitPersistedChoiceAndNothingIsSetByDefault() {
        let settings = MobileAISettings()
        XCTAssertNotEqual(settings.provider, .openAI, "A fresh install never starts on a custom server")
        XCTAssertFalse(settings.openAI.isConfigured)
        XCTAssertEqual(settings.openAI.providerLabel, "OpenAI-compatible server")
        settings.provider = .openAI
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mobileAIProvider"), "openai")
        XCTAssertEqual(MobileAISettings().provider, .openAI)
        XCTAssertEqual(settings.availability(for: .summary), "Set your OpenAI-compatible server URL in Settings.")
        XCTAssertThrowsError(try settings.client(for: .summary), "Nothing is sent without a server")
        XCTAssertFalse(settings.canRefreshSummaryModelsAutomatically)
    }

    func testServerValidationKeepsThePreviousServerAndLabelsTheDestinationHonestly() {
        let settings = MobileAISettings()
        settings.provider = .openAI
        XCTAssertTrue(settings.saveOpenAIBaseURL("http://studio.local:1234"))
        XCTAssertEqual(settings.openAI.baseURL, "http://studio.local:1234/v1")
        XCTAssertEqual(settings.openAI.providerLabel, "OpenAI-compatible · your server")
        XCTAssertEqual(settings.summaryEndpointLabel, "your server at studio.local:1234")
        XCTAssertEqual(settings.summaryEndpointTitle, "Your server at studio.local:1234")
        XCTAssertTrue(settings.status?.contains("cannot verify") == true, settings.status ?? "")

        for blocked in ["http://192.168.1.20:1234/v1", "http://openrouter.ai/api/v1", "https://u:p@host/v1", "nonsense"] {
            XCTAssertFalse(settings.saveOpenAIBaseURL(blocked), blocked)
            XCTAssertTrue(settings.status?.hasSuffix("The previous server is kept.") == true, settings.status ?? "")
            XCTAssertEqual(settings.openAI.baseURL, "http://studio.local:1234/v1", blocked)
        }

        XCTAssertTrue(settings.saveOpenAIBaseURL("https://openrouter.ai/api/v1"))
        XCTAssertEqual(settings.openAI.providerLabel, "OpenAI-compatible · may leave device")
        XCTAssertEqual(settings.summaryEndpointLabel, "openrouter.ai (may leave this device)")
        XCTAssertEqual(settings.summaryEndpointDescription, "https://openrouter.ai/api/v1")
        XCTAssertEqual(MobileAISettings().openAI.baseURL, "https://openrouter.ai/api/v1", "The choice survives relaunch")

        settings.clearOpenAIServer()
        XCTAssertFalse(settings.openAI.isConfigured)
        XCTAssertEqual(settings.summaryEndpointDescription, "no OpenAI-compatible server set")
    }

    func testTheKeyIsBoundToItsServerAndRemovedWhenTheServerChanges() throws {
        let settings = MobileAISettings()
        XCTAssertFalse(settings.saveOpenAIKey("sk-before-server"), "A key needs a server to belong to")
        XCTAssertTrue(settings.saveOpenAIBaseURL("https://openrouter.ai/api/v1"))
        XCTAssertTrue(settings.saveOpenAIKey("  sk-or-synthetic  "))
        XCTAssertTrue(settings.openAI.hasKey)
        XCTAssertEqual(try settings.openAI.currentKey(), "sk-or-synthetic")
        XCTAssertFalse(settings.status?.contains("sk-or-synthetic") == true, "A key is never echoed")

        // Same origin, different path: still the key's own server.
        XCTAssertTrue(settings.saveOpenAIBaseURL("https://openrouter.ai:443/api/v1/"))
        XCTAssertEqual(try settings.openAI.currentKey(), "sk-or-synthetic")

        // A different origin must never receive it.
        XCTAssertTrue(settings.saveOpenAIBaseURL("https://openrouter.ai.example.net/v1"))
        XCTAssertTrue(settings.status?.contains("API key was removed") == true, settings.status ?? "")
        XCTAssertFalse(settings.openAI.hasKey)
        XCTAssertEqual(try settings.openAI.currentKey(), "")
        XCTAssertEqual(try MobileKeychain.read(account: MobileKeychain.openAIAccount), "")

        // A mismatched origin record withholds a key even if one is somehow still stored.
        try MobileKeychain.save("sk-stray", account: MobileKeychain.openAIAccount)
        UserDefaults.standard.set("https://elsewhere.example:443", forKey: "mobileOpenAIKeyOrigin")
        XCTAssertEqual(try settings.openAI.currentKey(), "")
    }

    func testRoleModelsAreSeparateFromOllamaAndRouteEveryClientToTheServer() throws {
        let settings = MobileAISettings()
        let ollamaModel = settings.model
        settings.provider = .openAI
        XCTAssertTrue(settings.saveOpenAIBaseURL("http://localhost:1234/v1"))
        XCTAssertEqual(settings.availability(for: .summary), "Refresh models and choose a Summary model in Settings.")
        for mode in MobileSummaryMode.allCases { settings.selectModel("qwen3-8b", for: mode) }
        XCTAssertEqual(settings.model, ollamaModel, "Ollama selections are untouched")
        XCTAssertEqual(settings.selectedModel(for: .deep), "qwen3-8b", "Any listed model may serve Deep")
        for mode in MobileSummaryMode.allCases {
            XCTAssertNil(settings.availability(for: mode))
            let client = try XCTUnwrap(try settings.client(for: mode) as? OpenAICompatibleProvider)
            XCTAssertEqual(client.baseURL.absoluteString, "http://localhost:1234/v1")
            XCTAssertEqual(client.model, "qwen3-8b")
        }
        XCTAssertEqual(settings.transports.builtSessions, 1, "Every summary role shares one transport")
        settings.provider = .ollama
        XCTAssertEqual(settings.selectedModel(for: .summary), ollamaModel)
    }

    func testRefreshListsServerModelsAndFillsRolesOnlyWhenThereIsOneChoice() async throws {
        let settings = MobileAISettings()
        settings.provider = .openAI
        XCTAssertTrue(settings.saveOpenAIBaseURL("http://localhost:1234/v1"))
        XCTAssertTrue(settings.canRefreshSummaryModelsAutomatically, "A server the user entered is a chosen destination")
        OpenAIModelsStub.reply = #"{"data":[{"id":"qwen3-8b"}]}"#
        let count = try await settings.openAI.refresh(session: OpenAIModelsStub.session())
        XCTAssertEqual(count, 1)
        for mode in MobileSummaryMode.allCases { XCTAssertEqual(settings.selectedModel(for: mode), "qwen3-8b") }

        OpenAIModelsStub.reply = #"{"data":[{"id":"b-model"},{"id":"a-model"}]}"#
        settings.selectModel("", for: .deep)
        _ = try await settings.openAI.refresh(session: OpenAIModelsStub.session())
        XCTAssertEqual(settings.models(for: .deep).map(\.name), ["a-model", "b-model"])
        XCTAssertEqual(settings.selectedModel(for: .deep), "", "With several models the user chooses")
        XCTAssertEqual(settings.availability(for: .summary),
                       "The selected model is no longer listed by the server. Choose another model in Settings.")

        OpenAIModelsStub.reply = #"{"data":[]}"#
        do {
            _ = try await settings.openAI.refresh(session: OpenAIModelsStub.session())
            XCTFail("An empty list must be explained")
        } catch {
            XCTAssertTrue(MobileAISettings.errorMessage(error).contains("listed no models"))
        }
    }

    func testAutoPausesWithAReasonOnceTheQuickModelFailsTheJSONContract() {
        let settings = MobileAISettings()
        settings.provider = .openAI
        XCTAssertTrue(settings.saveOpenAIBaseURL("http://localhost:1234/v1"))
        settings.selectModel("tiny-model", for: .quick)
        XCTAssertNil(settings.automaticQuickReason, "An untested model is allowed and fails visibly if it must")
        settings.openAI.recordContract(passed: false)
        XCTAssertEqual(settings.automaticQuickReason,
                       "tiny-model did not follow the Quick Summary format. Choose another Quick model or test it again in Settings.")
        XCTAssertNotNil(MobileAISettings().automaticQuickReason, "The result survives relaunch")
        settings.selectModel("bigger-model", for: .quick)
        XCTAssertNil(settings.automaticQuickReason, "A different model starts fresh")
        settings.selectModel("tiny-model", for: .quick)
        settings.openAI.recordContract(passed: true)
        XCTAssertNil(settings.automaticQuickReason)
        settings.provider = .ollama
        settings.openAI.recordContract(passed: false)
        XCTAssertNil(settings.automaticQuickReason, "Only the OpenAI-compatible route is gated this way")
    }

    func testProviderChangesCancelObsoleteSummaryWork() {
        let settings = MobileAISettings()
        var changes = 0
        settings.quickSettingsChanged = { changes += 1 }
        XCTAssertTrue(settings.saveOpenAIBaseURL("http://localhost:1234/v1"))
        settings.selectModel("m", for: .quick)
        XCTAssertGreaterThanOrEqual(changes, 2, "Server and model changes reach the scheduler like Ollama's")
    }
}

/// Serves a fixed `/models` body to the catalog without touching the network.
final class OpenAIModelsStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: String?
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let reply = Self.reply,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIModelsStub.self]
        return URLSession(configuration: configuration)
    }
}
