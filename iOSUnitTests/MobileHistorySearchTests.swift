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
        let keys = ["mobileAIProvider", "mobileOllamaBaseURL", "mobileOllamaModel"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let summaryModel = session.ai.model
        let catalog = session.ai.models   // a catalog left by another test would not list the model below
        session.ai.models = []
        defer {
            session.ai.models = catalog
            session.ai.model = summaryModel
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        }
        session.ai.provider = .ollama
        XCTAssertTrue(session.ai.saveBaseURL("http://my-mac.local:11434"))
        session.ai.model = "llama3.1"
        let route = session.historyAskRoute
        XCTAssertNil(route.unavailable)
        XCTAssertEqual(route.destination, "http://my-mac.local:11434")
        XCTAssertEqual(route.disclosure, "Asking sends the matching excerpts (not whole conversations) and your "
                       + "question to http://my-mac.local:11434.")
    }

    func testDeletingEverythingWipesTheIndex() async throws {
        let (session, root) = makeSession()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = session.historySearch.index
        try await index.sync(session.history)
        session.forgetSearchIndex(ids: [], everything: true)
        await session.historySearch.waitForMaintenance()
        let ids = try await index.indexedIDs()
        XCTAssertTrue(ids.isEmpty)
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

/// Deleted conversations never come back through search (issue #57 review).
@MainActor
final class MobileHistorySearchDeletionTests: XCTestCase {
    private func record(_ id: String, _ text: String) -> SessionRecord {
        SessionRecord(id: id, title: id, date: Date(timeIntervalSince1970: 1_000), transcript: text, summary: "",
                      segments: [TranscriptSegment(source: .you, text: text, isFinal: true, start: 0, end: 1)])
    }

    func testADeleteDuringARunningSyncAndSearchLeavesNoTrace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GatedBudgetEmbedder()
        let model = HistorySearchModel(index: HistoryIndex(directory: root, embedder: gate),
                                       syncDelay: .zero, searchDelay: .zero)
        var current = (0..<6).map { record("r\($0)", "The budget and the funding.") }
        model.records = { current }
        model.sync(current)
        await gate.waitUntilEmbedding()          // the first build is running
        model.search("budget")                   // and a search waits behind it
        current.removeAll { $0.id == "r5" }      // the conversation is deleted from History…
        model.forget(id: "r5")                   // …and its owner entry runs
        gate.release()
        await model.waitForSync()
        await model.waitForSearch()

        let ids = try await model.index.indexedIDs()
        XCTAssertFalse(ids.contains("r5"), "The running sync must not write the deleted conversation's vectors")
        let shown = try XCTUnwrap(model.results(for: "budget"))
        XCTAssertFalse(shown.contains { $0.id == "r5" }, "A deleted conversation is never listed again")
        XCTAssertEqual(shown.count, 5)

        current = []
        model.forgetAll()
        await model.waitForMaintenance()
        await model.waitForSearch()
        let afterClear = try await model.index.indexedIDs()
        XCTAssertTrue(afterClear.isEmpty)
        XCTAssertEqual(model.results(for: "budget")?.count ?? 0, 0, "Clear history leaves nothing to list")
    }

    func testResultsAreForTheCurrentHistoryNotTheOneTheSearchStartedWith() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = HistorySearchModel(index: HistoryIndex(directory: root, embedder: GatedBudgetEmbedder(open: true)),
                                       syncDelay: .zero, searchDelay: .zero)
        var current = [record("a", "The budget.")]
        model.records = { current }
        model.search("budget")
        await model.waitForSearch()
        XCTAssertEqual(model.results(for: "budget")?.map(\.id), ["a"])
        // A newly saved conversation that matches is found without retyping the query.
        current.append(record("b", "The budget again."))
        model.update(current[1])
        await model.waitForSearch()
        XCTAssertEqual(Set(model.results(for: "budget")?.map(\.id) ?? []), ["a", "b"])
        XCTAssertNil(model.results(for: "other"), "Results belong to the query they were computed for")
    }

    func testOpeningADeletedConversationIsRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.title = "Budget review"; session.notes = "The budget."
        XCTAssertTrue(session.save(announce: false))
        session.newConversation()
        session.title = "Other"; session.notes = "Something else."
        XCTAssertTrue(session.save(announce: false))
        let stale = try XCTUnwrap(session.history.first { $0.title == "Budget review" })
        session.deleteConversation(id: stale.id)
        session.open(stale)   // e.g. a search row still on screen
        XCTAssertFalse(session.history.contains { $0.id == stale.id })
        XCTAssertFalse(try session.archive.read().records.contains { $0.id == stale.id },
                       "Opening a stale row must not write the deleted conversation back")
        XCTAssertNotEqual(session.title, "Budget review")
    }
}

/// One dimension: how much a passage is about money. The first `embed` waits until released.
private final class GatedBudgetEmbedder: HistoryEmbedder, @unchecked Sendable {
    let signature = "gated-budget-v1"
    private let lock = NSLock()
    private var started: Bool
    private var waiter: CheckedContinuation<Void, Never>?
    private let gate = DispatchSemaphore(value: 0)

    init(open: Bool = false) { started = open }

    func embed(_ text: String) -> HistoryVector? {
        lock.lock()
        let first = !started
        started = true
        let waiting = waiter
        waiter = nil
        lock.unlock()
        if first { waiting?.resume(); gate.wait() }
        return vector(text)
    }

    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] {
        models.contains("gate:en:1") ? [vector(query)] : []
    }

    private func vector(_ text: String) -> HistoryVector {
        let money = Float(["budget", "funding", "money"].filter { text.lowercased().contains($0) }.count)
        return HistoryVector(model: "gate:en:1", values: [money, 0.05])
    }

    func waitUntilEmbedding() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if started { lock.unlock(); continuation.resume(); return }
            waiter = continuation
            lock.unlock()
        }
    }

    func release() { gate.signal() }
}

/// "Ask your history" Stop really stops (issue #57 review).
@MainActor
final class MobileHistoryAskStopTests: XCTestCase {
    func testAStoppedAnswerNeverWritesOverTheNextOne() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = HistorySearchModel(index: HistoryIndex(directory: root, embedder: GatedBudgetEmbedder(open: true)),
                                       syncDelay: .zero, searchDelay: .zero)
        let records = [SessionRecord(id: "a", title: "Budget", date: Date(), transcript: "The budget is 40k.",
                                     summary: "")]
        model.records = { records }
        let slow = LateProvider(text: "Stale answer [1].")
        model.ask("budget", route: HistoryAskRoute(unavailable: nil, destination: nil, responseLanguage: nil,
                                                   makeProvider: { slow }))
        XCTAssertTrue(model.isAsking)
        await slow.waitUntilStreaming()   // the request is out; Stop arrives while it streams
        model.cancelAsk()
        XCTAssertFalse(model.isAsking)
        let fast = LateProvider(text: "Fresh answer [1].", immediate: true)
        model.ask("budget", route: HistoryAskRoute(unavailable: nil, destination: nil, responseLanguage: nil,
                                                   makeProvider: { fast }))
        await model.waitForAnswer()
        XCTAssertEqual(model.answer, "Fresh answer [1].")
        slow.release()
        await slow.waitUntilFinished()
        XCTAssertEqual(model.answer, "Fresh answer [1].", "The stopped request must not write its answer")
        XCTAssertFalse(model.isAsking)
        XCTAssertNil(model.askError)
        XCTAssertEqual(model.citations.map(\.recordID), ["a"])
    }
}

/// Streams `text` once released (or at once), ignoring cancellation like a slow server.
private final class LateProvider: LLMProvider, @unchecked Sendable {
    let id = "late"
    let text: String
    private let gate = DispatchSemaphore(value: 0)
    private let done = DispatchSemaphore(value: 0)
    private let streaming = DispatchSemaphore(value: 0)
    private let immediate: Bool
    init(text: String, immediate: Bool = false) { self.text = text; self.immediate = immediate }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let text = text, immediate = immediate, gate = gate, done = done
        streaming.signal()
        return AsyncThrowingStream { continuation in
            DispatchQueue.global().async {
                if !immediate { gate.wait() }
                continuation.yield(text)
                continuation.finish()
                done.signal()
            }
        }
    }
    func release() { gate.signal() }
    func waitUntilStreaming() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { self.streaming.wait(); continuation.resume() }
        }
    }
    func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { self.done.wait(); continuation.resume() }
        }
        await Task.yield()
    }
}
