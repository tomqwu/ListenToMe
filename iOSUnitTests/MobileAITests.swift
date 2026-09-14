import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileAITests: XCTestCase {
    func testFreshSettingsDefaultToOnDeviceAndPreserveAnyExplicitChoice() {
        let previous = UserDefaults.standard.object(forKey: "mobileAIProvider")
        defer { UserDefaults.standard.set(previous, forKey: "mobileAIProvider") }
        UserDefaults.standard.removeObject(forKey: "mobileAIProvider")
        let expected: MobileAISettings.Provider =
            AppleIntelligenceProvider.unavailableReason == nil ? .apple : .ollama
        XCTAssertEqual(MobileAISettings.defaultProvider, expected)
        XCTAssertEqual(MobileAISettings().provider, expected)
        // A saved choice from an earlier build must survive the new default.
        for choice in MobileAISettings.Provider.allCases {
            UserDefaults.standard.set(choice.rawValue, forKey: "mobileAIProvider")
            XCTAssertEqual(MobileAISettings().provider, choice)
        }
        UserDefaults.standard.set("no-longer-a-provider", forKey: "mobileAIProvider")
        XCTAssertEqual(MobileAISettings().provider, expected)
    }

    /// Both branches of the default are checked directly, not only the one this machine happens to take.
    func testDefaultProviderIsOnDeviceUnlessAppleIntelligenceIsUnavailable() {
        XCTAssertEqual(MobileAISettings.defaultProvider(unavailableReason: nil), .apple)
        XCTAssertEqual(MobileAISettings.defaultProvider(unavailableReason: "Device not eligible."), .ollama)
        XCTAssertEqual(MobileAISettings.defaultProvider,
                       MobileAISettings.defaultProvider(unavailableReason: MobileAISettings.defaultProviderReason))
        XCTAssertEqual(MobileAISettings.defaultProviderReason, AppleIntelligenceProvider.unavailableReason)
    }

    func testFallbackExplanationAppearsOnlyForTheUnchosenOllamaFallback() {
        let previous = UserDefaults.standard.object(forKey: "mobileAIProvider")
        defer { UserDefaults.standard.set(previous, forKey: "mobileAIProvider") }
        UserDefaults.standard.removeObject(forKey: "mobileAIProvider")
        let fresh = MobileAISettings()
        XCTAssertFalse(fresh.hasSavedProviderChoice)
        if MobileAISettings.defaultProviderReason == nil {
            XCTAssertEqual(fresh.provider, .apple)
            XCTAssertNil(fresh.fallbackExplanation, "An on-device default has nothing to explain")
        } else {
            XCTAssertEqual(fresh.provider, .ollama)
            XCTAssertEqual(fresh.fallbackExplanation, MobileAISettings.defaultProviderReason)
        }
        // Choosing Apple by hand must never claim the device fell back to Ollama.
        fresh.provider = .apple
        XCTAssertTrue(fresh.hasSavedProviderChoice)
        XCTAssertNil(fresh.fallbackExplanation)
        // Choosing Ollama by hand is a choice, not a fallback.
        fresh.provider = .ollama
        XCTAssertNil(fresh.fallbackExplanation)
        XCTAssertNil(MobileAISettings().fallbackExplanation, "A saved choice is never a fallback")
    }

    func testCustomBaseURLIsValidatedAndNeverAutoSelected() {
        let previous = UserDefaults.standard.object(forKey: "mobileOllamaBaseURL")
        defer { UserDefaults.standard.set(previous, forKey: "mobileOllamaBaseURL") }
        UserDefaults.standard.removeObject(forKey: "mobileOllamaBaseURL")
        let settings = MobileAISettings()
        XCTAssertEqual(settings.ollamaBaseURL, "")
        XCTAssertFalse(settings.usesCustomEndpoint)
        XCTAssertEqual(settings.resolvedBaseURL, OllamaCloudCatalog.baseURL)
        XCTAssertEqual(settings.endpointDescription, "https://ollama.com")

        XCTAssertTrue(settings.saveBaseURL("  http://studio.local:11434/  "))
        XCTAssertTrue(settings.usesCustomEndpoint)
        XCTAssertEqual(settings.resolvedBaseURL.absoluteString, "http://studio.local:11434")
        XCTAssertEqual(settings.endpointDescription, "http://studio.local:11434")
        XCTAssertEqual(MobileAISettings().resolvedBaseURL.absoluteString, "http://studio.local:11434")

        for invalid in ["studio.local:11434", "ftp://studio.local", "http://", "not a url"] {
            XCTAssertFalse(settings.saveBaseURL(invalid), invalid)
            XCTAssertEqual(settings.resolvedBaseURL.absoluteString, "http://studio.local:11434", invalid)
            XCTAssertEqual(settings.status,
                           "That server address is not a valid http:// or https:// URL. "
                           + "The previous server is kept.", invalid)
        }
        // ATS only exempts plain http for .local/link-local/loopback, so a private IPv4 literal is
        // refused with the .local form named rather than failing opaquely at request time.
        for blocked in ["http://192.168.1.10:11434", "http://10.0.0.4:11434", "http://172.20.3.9:11434"] {
            XCTAssertFalse(settings.saveBaseURL(blocked), blocked)
            XCTAssertEqual(settings.resolvedBaseURL.absoluteString, "http://studio.local:11434", blocked)
            XCTAssertTrue(settings.status?.contains("your-mac.local") == true, settings.status ?? "")
        }
        // https to the same addresses is not an ATS problem, and loopback stays usable.
        XCTAssertTrue(settings.saveBaseURL("https://192.168.1.10:11434"))
        XCTAssertTrue(settings.saveBaseURL("http://127.0.0.1:11434"))
        XCTAssertTrue(settings.saveBaseURL("http://studio.local:11434"))

        // Typing the cloud host by hand is the cloud, not "your server".
        XCTAssertTrue(settings.saveBaseURL("https://ollama.com"))
        XCTAssertFalse(settings.usesCustomEndpoint)
        XCTAssertEqual(settings.resolvedBaseURL, OllamaCloudCatalog.baseURL)
        XCTAssertEqual(settings.endpointLabel, "Ollama Cloud")
        XCTAssertTrue(settings.saveBaseURL("http://studio.local:11434"))
        XCTAssertTrue(settings.usesCustomEndpoint)
        XCTAssertEqual(settings.endpointLabel, "http://studio.local:11434")

        XCTAssertTrue(settings.saveBaseURL(""))
        XCTAssertFalse(settings.usesCustomEndpoint)
        XCTAssertEqual(settings.resolvedBaseURL, OllamaCloudCatalog.baseURL)
    }

    func testCustomEndpointMakesTheAPIKeyOptionalAndRoutesEveryClient() throws {
        let original = try MobileKeychain.read()
        let previousURL = UserDefaults.standard.object(forKey: "mobileOllamaBaseURL")
        let settings = MobileAISettings()
        let provider = settings.provider, model = settings.model
        let quick = settings.quickModel, deep = settings.deepModel, correction = settings.correctionModel
        defer {
            settings.provider = provider; settings.model = model
            settings.quickModel = quick; settings.deepModel = deep; settings.correctionModel = correction
            UserDefaults.standard.set(previousURL, forKey: "mobileOllamaBaseURL")
            try? MobileKeychain.save(original)
        }
        settings.saveKey("")
        settings.saveBaseURL("")
        settings.provider = .ollama
        settings.models = [OllamaCloudModel(name: "glm-5.3:local"), OllamaCloudModel(name: "glm-5.3-flash:local")]
        settings.model = "glm-5.3:local"; settings.deepModel = "glm-5.3:local"
        settings.quickModel = "glm-5.3-flash:local"
        settings.correctionModel = "glm-5.3-flash:local"
        // Cloud still demands a key.
        XCTAssertEqual(settings.availability(for: .summary), "Add your Ollama API key in Settings.")
        XCTAssertEqual(settings.correctionAvailability, "Add your Ollama API key in AI settings.")
        XCTAssertThrowsError(try settings.client())

        XCTAssertTrue(settings.saveBaseURL("http://studio.local:11434"))
        XCTAssertNil(settings.availability(for: .summary))
        XCTAssertNil(settings.correctionAvailability)
        for mode in MobileSummaryMode.allCases {
            XCTAssertEqual(try settings.client(for: mode).baseURL.absoluteString, "http://studio.local:11434")
        }
        XCTAssertEqual(try settings.correctionClient().baseURL.absoluteString, "http://studio.local:11434")
    }

    func testTheCloudAPIKeyIsNeverSentToAServerTheUserEntered() throws {
        let original = try MobileKeychain.read()
        let previousURL = UserDefaults.standard.object(forKey: "mobileOllamaBaseURL")
        defer {
            UserDefaults.standard.set(previousURL, forKey: "mobileOllamaBaseURL")
            try? MobileKeychain.save(original)
        }
        let settings = MobileAISettings()
        settings.saveKey("synthetic-cloud-key")
        XCTAssertTrue(settings.saveBaseURL(""))
        XCTAssertEqual(try settings.apiKey(forEndpoint: settings.resolvedBaseURL),
                       "synthetic-cloud-key", "Ollama Cloud is the credential's own service")
        XCTAssertTrue(settings.saveBaseURL("http://studio.local:11434"))
        XCTAssertEqual(try settings.apiKey(forEndpoint: settings.resolvedBaseURL), "",
                       "A private endpoint must not be able to collect the cloud key")
        XCTAssertEqual(try MobileKeychain.read(), "synthetic-cloud-key", "The key is withheld, not deleted")
    }

    func testCatalogIsAvailableAfterSettingsRelaunch() {
        let previous = UserDefaults.standard.string(forKey: "mobileOllamaCatalog")
        defer { UserDefaults.standard.set(previous, forKey: "mobileOllamaCatalog") }
        let settings = MobileAISettings()
        settings.models = [.init(name: "quick-test"), .init(name: "deep-test")]
        XCTAssertEqual(MobileAISettings().models, settings.models)
    }

    func testCloudFailureMessagesDoNotClaimUnsavedPartialIsKept() {
        XCTAssertEqual(MobileAISettings.errorMessage(OllamaStreamError.incomplete),
                       "Ollama's response ended before completion.")
        XCTAssertEqual(MobileAISettings.errorMessage(CancellationError()), "Request cancelled.")
        XCTAssertEqual(MobileAISettings.errorMessage(URLError(.networkConnectionLost)), "The internet connection was lost.")
        XCTAssertTrue(MobileAISettings.errorMessage(URLError(.notConnectedToInternet)).contains("offline"))
        XCTAssertTrue(MobileAISettings.errorMessage(URLError(.timedOut)).contains("timed out"))
        XCTAssertTrue(MobileAISettings.errorMessage(NSError(domain: "Ollama", code: 401)).contains("HTTP 401"))
    }

    func testKeychainCreateReplaceReadAndDelete() throws {
        let original = try MobileKeychain.read()
        defer { try? MobileKeychain.save(original) }
        try MobileKeychain.save("synthetic-test-key")
        XCTAssertEqual(try MobileKeychain.read(), "synthetic-test-key")
        try MobileKeychain.save("replacement-test-key")
        XCTAssertEqual(try MobileKeychain.read(), "replacement-test-key")
        try MobileKeychain.save("")
        XCTAssertEqual(try MobileKeychain.read(), "")
        try MobileKeychain.save("")
    }

    func testSettingsPersistenceAndUnavailableModelGuard() throws {
        let original = try MobileKeychain.read()
        let settings = MobileAISettings()
        let provider = settings.provider, model = settings.model
        defer { settings.provider = provider; settings.model = model; try? MobileKeychain.save(original) }
        settings.saveKey("  synthetic-key  ")
        XCTAssertTrue(settings.hasKey)
        XCTAssertEqual(try MobileKeychain.read(), "synthetic-key")
        settings.provider = .ollama
        settings.model = "future-model"
        let reloaded = MobileAISettings()
        XCTAssertEqual(reloaded.provider, .ollama)
        XCTAssertEqual(reloaded.model, "future-model")
        XCTAssertTrue(reloaded.hasKey)
        reloaded.models = [OllamaCloudModel(name: "different-model")]
        XCTAssertNotNil(reloaded.availability)
        reloaded.model = "different-model"
        XCTAssertNil(reloaded.availability)
        reloaded.saveKey("")
        XCTAssertNotNil(reloaded.availability)
        XCTAssertThrowsError(try reloaded.client())
    }

    /// Opt-in: stage a key locally in the test app container. No credential is committed or logged.
    func testLiveCloudCatalogConnectionAndSummary() async throws {
        let keyFile = URL.applicationSupportDirectory.appendingPathComponent("OllamaLiveTestKey")
        guard FileManager.default.fileExists(atPath: keyFile.path) else {
            throw XCTSkip("Live cloud test requires a locally staged credential.")
        }
        let original = try MobileKeychain.read()
        let key = try String(contentsOf: keyFile, encoding: .utf8)
        try FileManager.default.removeItem(at: keyFile)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        let originalAuto = session.autoQuick
        session.autoQuick = false
        let originalProvider = session.ai.provider, originalModel = session.ai.model
        let originalQuick = session.ai.quickModel, originalDeep = session.ai.deepModel
        defer {
            session.state = .idle; session.autoQuick = originalAuto
            try? MobileKeychain.save(original)
            session.ai.provider = originalProvider; session.ai.model = originalModel
            session.ai.quickModel = originalQuick; session.ai.deepModel = originalDeep
        }
        session.ai.saveKey(key)
        session.ai.provider = .ollama
        session.ai.model = ""
        await session.ai.refresh()
        XCTAssertFalse(session.ai.models.isEmpty)
        XCTAssertNil(session.ai.availability)
        await session.ai.testConnection()
        XCTAssertTrue(session.ai.status?.contains("Connection verified") == true, session.ai.status ?? "No status")
        session.newConversation()
        session.notes = "Decision: review the mobile release on Friday. Alex will prepare the checklist."
        await session.summarize()
        XCTAssertNil(session.message)
        XCTAssertTrue(session.summary.localizedCaseInsensitiveContains("Friday"))
        XCTAssertTrue(session.summary.localizedCaseInsensitiveContains("Alex"))
        XCTAssertFalse(session.isSummarizing)
        XCTAssertEqual(MobileSession(storageDirectory: root).summary, session.summary)
        let fullSummary = session.summary
        for mode in [MobileSummaryMode.quick, .deep] {
            session.ai.selectModel(session.ai.model, for: mode)
            await session.summarize(mode: mode)
            XCTAssertNil(session.message)
            XCTAssertFalse(session.output(for: mode).isEmpty)
            XCTAssertEqual(session.summary, fullSummary)
            XCTAssertEqual(MobileSession(storageDirectory: root).output(for: mode), session.output(for: mode))
        }
        // Exercise the automatic tick with a synthetic recording state; this does not validate microphone capture.
        let completedDeep = session.deepThought
        session.notes += " New decision: move the review to Monday. Jordan owns the final sign-off."
        session.state = .recording
        await session.updateQuickAutomatically()
        XCTAssertFalse(session.isSummarizing, "Auto must be opt-in")
        session.quickSummary = "Old quick summary"
        session.autoQuick = true
        await session.updateQuickAutomatically()
        for _ in 0..<480 {
            try await Task.sleep(for: .seconds(1))
            if !session.isSummarizing && (session.quickSummary != "Old quick summary" || session.message != nil) { break }
        }
        XCTAssertNil(session.message)
        XCTAssertNotEqual(session.quickSummary, "Old quick summary")
        XCTAssertEqual(session.deepThought, completedDeep)
        await session.updateQuickAutomatically()
        await Task.yield()
        XCTAssertFalse(session.isSummarizing, "An unchanged transcript must not send another request")
        session.state = .idle
        let goodSummary = session.summary
        session.ai.saveKey("invalid-key-for-negative-test")
        await session.summarize()
        XCTAssertNotNil(session.message)
        XCTAssertEqual(session.summary, goodSummary, "Failed cloud requests must keep the completed summary")
    }

    func testManualSummaryAndDeepGroundingExplainsTypedNotes() {
        let notesExplanation = "a line prefixed \"Notes: \" is the user's typed " +
            "note, not speech, and must never be reported as something that was said in the meeting."
        for mode in [MobileSummaryMode.summary, .deep] {
            XCTAssertTrue(mode.instructions.contains(notesExplanation),
                          "\(mode) instructions must ground the model on typed notes")
        }
    }
}
