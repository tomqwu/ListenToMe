import Foundation
import ListenToMeCore
import XCTest

private actor TransitionEmbedder: HistoryEmbedder {
    nonisolated let signature: String
    private let available: Bool
    private var holdQueries = false
    private var heldPassage: String?
    private var holdNextPassage = false
    private var passageWaiter: CheckedContinuation<Void, Never>?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var passageCalls = 0
    init(_ signature: String, available: Bool = true) { self.signature = signature; self.available = available }
    func embed(_ text: String) async -> HistoryVector? {
        passageCalls += 1
        if heldPassage == text || holdNextPassage {
            holdNextPassage = false
            await withCheckedContinuation { passageWaiter = $0 }
        }
        return available ? HistoryVector(model: signature, values: [1, 0]) : nil
    }
    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        if holdQueries { await withCheckedContinuation { waiting.append($0) } }
        return available && models.contains(signature) ? [HistoryVector(model: signature, values: [1, 0])] : []
    }
    func holdPassage(_ text: String) { heldPassage = text }
    func holdNext() { holdNextPassage = true }
    func isPassageWaiting() -> Bool { passageWaiter != nil }
    func releasePassage() { heldPassage = nil; let old = passageWaiter; passageWaiter = nil; old?.resume() }
    func hold() { holdQueries = true }
    func isWaiting() -> Bool { !waiting.isEmpty }
    func release() { holdQueries = false; let old = waiting; waiting = []; old.forEach { $0.resume() } }
}

private final class TransitionProvider: LLMProvider, @unchecked Sendable {
    let id = "transition-provider"
    private let lock = NSLock()
    private var calls = 0
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private let immediate: String?
    init(immediate: String? = nil) { self.immediate = immediate }
    var count: Int { lock.withLock { calls } }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { output in
            lock.withLock { calls += 1; continuation = output }
            if let immediate { output.yield(immediate); output.finish() }
        }
    }
    func release(_ text: String) {
        let output = lock.withLock { let value = continuation; continuation = nil; return value }
        output?.yield(text); output?.finish()
    }
}

@MainActor
final class HistoryBackendTransitionTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func record(_ id: String = "old", text: String = "private alpha secret") -> SessionRecord {
        SessionRecord(id: id, title: id, date: Date(timeIntervalSince1970: 0), transcript: text, summary: "")
    }
    private func route(_ provider: TransitionProvider) -> HistoryAskRoute {
        HistoryAskRoute(unavailable: nil, destination: nil, responseLanguage: nil, makeProvider: { provider })
    }
    private func wait(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<150 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The real request must reach the controlled suspension")
        return false
    }
    private func obstruct(_ directory: URL) throws -> URL {
        let saved = directory.appendingPathExtension("saved")
        try FileManager.default.moveItem(at: directory, to: saved)
        try Data("obstruct derived storage".utf8).write(to: directory)
        return saved
    }
    private func restore(_ directory: URL, _ saved: URL) throws {
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: saved, to: directory)
    }

    func testFailedSwitchBlocksOldSemanticsAndAskUntilSyncRetry() async throws {
        let folder = directory(); let saved = folder.appendingPathExtension("saved")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: saved) }
        let old = TransitionEmbedder("optional-old"); let fallback = TransitionEmbedder("fallback", available: false)
        let index = HistoryIndex(directory: folder, embedder: old)
        let rows = [record()]; try await index.sync(rows)
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero); model.records = { rows }
        _ = try obstruct(folder)
        model.setEmbedder(fallback); await model.waitForMaintenance()
        try restore(folder, saved)
        model.search("meaning"); await model.waitForSearch()
        XCTAssertTrue(model.results(for: "meaning")?.isEmpty == true, "An old optional backend must not resume after opt-out fails")
        model.search("secret"); await model.waitForSearch()
        let lexical = try XCTUnwrap(model.results(for: "secret"))
        XCTAssertEqual(lexical.map(\.id), [rows[0].id]); XCTAssertTrue(lexical.allSatisfy { $0.matchesWords && !$0.isRelated })
        let provider = TransitionProvider(immediate: "Unwanted old answer [1].")
        model.ask("meaning", route: route(provider)); await model.waitForAnswer()
        XCTAssertEqual(provider.count, 0, "No Ask dispatch may use a backend the user just disabled")
        XCTAssertEqual(model.answer, ""); XCTAssertTrue(model.citations.isEmpty); XCTAssertNotNil(model.askError)
        model.sync(rows); await model.waitForSync()
        let attempted = await fallback.passageCalls; XCTAssertGreaterThan(attempted, 0, "Sync must retry the intended backend")
        model.search("meaning"); await model.waitForSearch()
        XCTAssertTrue(model.results(for: "meaning")?.isEmpty == true)
        let allowed = TransitionProvider(immediate: "Current keyword answer [1].")
        model.ask("secret", route: route(allowed)); await model.waitForAnswer()
        XCTAssertEqual(allowed.count, 1, "Keyword Ask is usable after the intended backend is installed")
        XCTAssertEqual(model.citations.map(\.recordID), [rows[0].id])
    }

    func testSaveRetriesIntendedBackendAfterStorageRecovery() async throws {
        let folder = directory(); let saved = folder.appendingPathExtension("saved")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: saved) }
        let old = TransitionEmbedder("optional-old"); let replacement = TransitionEmbedder("new-backend")
        let index = HistoryIndex(directory: folder, embedder: old)
        var rows = [record()]; try await index.sync(rows)
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero); model.records = { rows }
        _ = try obstruct(folder)
        model.setEmbedder(replacement); await model.waitForMaintenance(); try restore(folder, saved)
        rows = [record(text: "current beta replacement")]
        model.update(rows[0]); await model.waitForUpdates()
        let attempted = await replacement.passageCalls; XCTAssertGreaterThan(attempted, 0)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("index.json"))) as? [String: Any]
        XCTAssertEqual(manifest?["embedder"] as? String, replacement.signature)
        model.search("meaning"); await model.waitForSearch()
        XCTAssertEqual(model.results(for: "meaning")?.first?.snippet?.text, rows[0].transcript)
    }

    func testHeldOldSearchCannotRestorePreviousConversationAfterSwitch() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let old = TransitionEmbedder("optional-old"); let replacement = TransitionEmbedder("new-backend")
        let index = HistoryIndex(directory: folder, embedder: old)
        var rows = [record()]; try await index.sync(rows)
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero); model.records = { rows }
        await old.hold()
        let earlier = Task { model.search("meaning"); await model.waitForSearch() }
        guard await wait({ await old.isWaiting() }) else { await old.release(); await earlier.value; return }
        rows = [record("current", text: "new current conversation")]
        model.setEmbedder(replacement); model.forget(id: "old")
        await model.waitForMaintenance(); await model.waitForSearch()
        await old.release(); await earlier.value
        model.search("meaning"); await model.waitForSearch()
        let results = try XCTUnwrap(model.results(for: "meaning"))
        XCTAssertEqual(results.map(\.id), ["current"]); XCTAssertEqual(results.first?.snippet?.text, rows[0].transcript)
        let ids = try await index.indexedIDs(); XCTAssertEqual(ids, ["current"])
    }

    func testHeldOldAnswerCannotReplaceCurrentAnswerAfterSwitch() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let index = HistoryIndex(directory: folder, embedder: TransitionEmbedder("optional-old"))
        var rows = [record()]; try await index.sync(rows)
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero); model.records = { rows }
        let slow = TransitionProvider()
        let earlier = Task { model.ask("meaning", route: route(slow)); await model.waitForAnswer() }
        guard await wait({ slow.count == 1 }) else { slow.release("cleanup"); await earlier.value; return }
        rows = [record("current", text: "new current conversation")]
        model.setEmbedder(TransitionEmbedder("new-backend"))
        XCTAssertEqual(model.answer, ""); XCTAssertTrue(model.citations.isEmpty); XCTAssertFalse(model.isAsking)
        await model.waitForMaintenance()
        let current = TransitionProvider(immediate: "Current answer [1].")
        model.ask("meaning", route: route(current)); await model.waitForAnswer()
        slow.release("Old private answer [1]."); await earlier.value
        XCTAssertEqual(model.answer, "Current answer [1]."); XCTAssertEqual(model.citations.map(\.recordID), ["current"])
        XCTAssertEqual(current.count, 1)
    }
    func testNewAndEditedSavesRefreshActiveSemanticSearchWithoutRetyping() async throws {
        for append in [true, false] {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let embedder = TransitionEmbedder("ready-backend")
            let index = HistoryIndex(directory: folder, embedder: embedder)
            var rows = [record()]; try await index.sync(rows)
            let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero)
            model.records = { rows }
            model.search("meaning"); await model.waitForSearch()
            XCTAssertEqual(model.results(for: "meaning")?.map(\.id), ["old"])
            let saved = record(append ? "new" : "old", text: "current saved passage")
            rows = append ? rows + [saved] : [saved]
            await embedder.holdPassage(saved.transcript)
            model.update(saved)
            guard await wait({ await embedder.isPassageWaiting() }) else {
                await embedder.releasePassage(); await model.waitForUpdates(); continue
            }
            // Settle the search started before publication; it cannot yet use the new vectors.
            await model.waitForSearch()
            XCTAssertFalse(model.results(for: "meaning")?.contains { $0.id == saved.id && $0.snippet?.text == saved.transcript } == true)
            await embedder.releasePassage(); await model.waitForUpdates(); await model.waitForSearch()
            let results = model.results(for: "meaning") ?? []
            XCTAssertEqual(Set(results.map(\.id)), Set(rows.map(\.id)))
            XCTAssertEqual(results.first { $0.id == saved.id }?.snippet?.text, saved.transcript)
        }
    }

    func testSupersededHeldSaveCannotRefreshNewBackendEpoch() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let old = TransitionEmbedder("optional-old"); let index = HistoryIndex(directory: folder, embedder: old)
        var rows = [record()]; try await index.sync(rows)
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero); model.records = { rows }
        let changed = record(text: "held changed passage"); rows = [changed]
        await old.holdPassage(changed.transcript)
        let earlier = Task { model.update(changed); await model.waitForUpdates() }
        guard await wait({ await old.isPassageWaiting() }) else {
            await old.releasePassage(); await earlier.value; return
        }
        rows = [record("current", text: "current conversation")]
        model.setEmbedder(TransitionEmbedder("new-backend"))
        await model.waitForMaintenance()
        model.search("current"); await model.waitForSearch()
        let generation = model.generation
        let shown = model.results(for: "current")?.map(\.id)
        await old.releasePassage(); await earlier.value
        XCTAssertEqual(model.generation, generation, "A cancelled previous maintenance epoch must not refresh the current search")
        XCTAssertEqual(model.results(for: "current")?.map(\.id), shown)
        XCTAssertEqual(shown, ["current"])
    }

    func testClearRevokesOlderSaveBatchBehindQueuedMaintenance() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let embedder = TransitionEmbedder("ready-backend"); let index = HistoryIndex(directory: folder, embedder: embedder)
        let baseline = record("baseline"); try await index.sync([baseline])
        let first = record("first", text: "first saved secret")
        let second = record("second", text: "second saved secret")
        var rows = [baseline, first, second]
        let model = HistorySearchModel(index: index, syncDelay: .zero, searchDelay: .zero); model.records = { rows }
        await embedder.holdNext()
        model.update(first); model.update(second)
        let older = await model.waitForUpdateEnqueue()
        guard await wait({ await embedder.isPassageWaiting() }) else {
            await embedder.releasePassage(); await older?.value; return
        }
        let later = record("later", text: "queued later secret"); rows.append(later)
        model.update(later)
        _ = await model.waitForUpdateEnqueue() // The latest wrapper now waits behind the held older batch.
        rows = []; model.forgetAll()
        guard await wait({ (try? await index.indexedIDs().isEmpty) == true }) else {
            await embedder.releasePassage(); await older?.value; await model.waitForMaintenance(); return
        }
        let generation = model.generation
        await embedder.releasePassage(); await older?.value; await model.waitForMaintenance()
        let ids = try await index.indexedIDs(); XCTAssertTrue(ids.isEmpty, "Unvisited records from the older batch must not be written after Clear")
        XCTAssertEqual(model.generation, generation, "Old save completion must not refresh the cleared epoch")
    }

}
