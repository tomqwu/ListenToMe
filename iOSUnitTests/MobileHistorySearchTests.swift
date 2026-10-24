import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Answers like an on-device model and records what it was sent.
private final class CitingProvider: LLMProvider, @unchecked Sendable {
    let id = "citing-test"
    let response: String
    private(set) var request: LLMRequest?
    init(response: String) { self.response = response }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        self.request = request
        let response = response
        return AsyncThrowingStream { continuation in continuation.yield(response); continuation.finish() }
    }
}

/// History search and "Ask your history" on iPhone (issue #57).
@MainActor
final class MobileHistorySearchTests: XCTestCase {
    private func makeSession() -> (MobileSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = MobileSession(storageDirectory: root)
        session.title = "Budget review"
        session.notes = "The quarterly budget is forty thousand dollars. Finance approved the funding."
        XCTAssertTrue(session.save(announce: false))
        session.newConversation()
        session.title = "Offsite planning"
        session.notes = "Book the flight and the hotel in Berlin for the team offsite."
        XCTAssertTrue(session.save(announce: false))
        return (session, root)
    }

    func testTheIndexLivesBesideTheArchiveOutsideBackups() async throws {
        let (session, root) = makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = session.historySearch.index
        XCTAssertEqual(index.directory.standardizedFileURL.path,
                       root.appendingPathComponent("Search Index").standardizedFileURL.path)
        try await index.sync(session.history)
        let ids = try await index.indexedIDs()
        XCTAssertEqual(ids, Set(session.history.map(\.id)))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(index.directory), "Derived data never enters a backup")
    }

    func testAskSendsOnlyTheRetrievedExcerptsAndCitesTheirConversation() async throws {
        let (session, root) = makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let budget = try XCTUnwrap(session.history.first { $0.title == "Budget review" })
        try await session.historySearch.index.sync(session.history)
        let provider = CitingProvider(response: "Forty thousand dollars [1].")
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .apple
        session.onDeviceProviderOverride = provider
        XCTAssertNil(session.historyAskRoute.unavailable)
        XCTAssertNil(session.historyAskRoute.disclosure, "Apple Intelligence answers on this iPhone")

        session.askHistory("What is the budget?")
        await session.historySearch.waitForAnswer()

        XCTAssertNil(session.historySearch.askError, session.historySearch.askError ?? "")
        XCTAssertEqual(session.historySearch.answer, "Forty thousand dollars [1].")
        XCTAssertEqual(session.historySearch.citations.map(\.recordID), [budget.id])
        let sent = try XCTUnwrap(provider.request?.messages.first?.content)
        XCTAssertTrue(sent.contains("forty thousand dollars"))
        XCTAssertFalse(sent.contains("Berlin"), "A conversation that does not match is never sent")
    }

    func testAnOffDeviceProviderIsNamedBeforeAnythingIsSent() {
        let (session, root) = makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = ["mobileAIProvider", "mobileOllamaBaseURL", "mobileOllamaDeepModel"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let deep = session.ai.deepModel
        defer {
            session.ai.deepModel = deep
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        }
        session.ai.provider = .ollama
        XCTAssertTrue(session.ai.saveBaseURL("http://my-mac.local:11434"))
        session.ai.deepModel = "llama3.1"
        let route = session.historyAskRoute
        XCTAssertNil(route.unavailable)
        XCTAssertEqual(route.destination, "http://my-mac.local:11434")
        XCTAssertEqual(route.disclosure, "Asking sends the matching excerpts (not whole conversations) and your "
                       + "question to http://my-mac.local:11434.")
    }

    func testDeletingAConversationRemovesItsVectors() async throws {
        let (session, root) = makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = session.historySearch.index
        try await index.sync(session.history)
        let budget = try XCTUnwrap(session.history.first { $0.title == "Budget review" })
        session.deleteConversation(id: budget.id)
        await session.historySearch.waitForMaintenance()
        let ids = try await index.indexedIDs()
        XCTAssertFalse(ids.contains(budget.id))
        XCTAssertEqual(ids.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: index.directory.appendingPathComponent("\(budget.id).vectors").path))
    }
}
