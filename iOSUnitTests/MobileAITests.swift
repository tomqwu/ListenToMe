import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileAITests: XCTestCase {
    func testCloudFailureMessagesDoNotClaimUnsavedPartialIsKept() {
        XCTAssertEqual(MobileAISettings.errorMessage(OllamaStreamError.incomplete),
                       "Ollama's response ended before completion.")
        XCTAssertEqual(MobileAISettings.errorMessage(CancellationError()), "Request cancelled.")
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
        let session = MobileSession()
        let originalProvider = session.ai.provider, originalModel = session.ai.model
        defer {
            try? MobileKeychain.save(original)
            session.ai.provider = originalProvider; session.ai.model = originalModel
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
        XCTAssertEqual(MobileSession().summary, session.summary)
        let goodSummary = session.summary
        session.ai.saveKey("invalid-key-for-negative-test")
        await session.summarize()
        XCTAssertNotNil(session.message)
        XCTAssertEqual(session.summary, goodSummary, "Failed cloud requests must keep the completed summary")
    }
}
