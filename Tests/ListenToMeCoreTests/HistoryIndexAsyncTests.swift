import XCTest
@testable import ListenToMeCore

private actor SuspendedHistoryEmbedder: HistoryEmbedder {
    nonisolated let signature: String
    init(signature: String = "async-held-v1") { self.signature = signature }
    private var heldText: String?
    private var holdsQuery = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var entered = false
    private(set) var languages: [String] = []

    func hold(text: String? = nil, query: Bool = false) { heldText = text; holdsQuery = query; entered = false }
    func isWaiting() -> Bool { entered }
    func release() { let pending = waiting; waiting = nil; heldText = nil; holdsQuery = false; pending?.resume() }
    private func pause() async {
        entered = true
        await withCheckedContinuation { waiting = $0 }
    }
    func embed(_ text: String) async -> HistoryVector? {
        if heldText == text { await pause() }
        return vector(text)
    }
    func embed(_ text: String, transcribedIn language: String) async -> HistoryVector? {
        languages.append(language)
        return await embed(text)
    }
    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        if holdsQuery { await pause() }
        return models.contains(signature) ? [vector(query)] : []
    }
    private func vector(_ text: String) -> HistoryVector {
        HistoryVector(model: signature, values: text.contains("beta") ? [0, 1] : [1, 0])
    }
}

@MainActor
final class HistoryIndexAsyncTests: XCTestCase {
    private func record(_ id: String = "record", text: String = "alpha secret", summary: String = "") -> SessionRecord {
        SessionRecord(id: id, title: id, date: Date(timeIntervalSince1970: 0), transcript: text, summary: summary)
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func wait(_ embedder: SuspendedHistoryEmbedder) async -> Bool {
        for _ in 0..<150 {
            if await embedder.isWaiting() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The actual embedding request must reach the held inference")
        return false
    }
    private func file(_ directory: URL, id: String = "record") -> URL {
        directory.appendingPathComponent(id + ".vectors")
    }

    func testAsyncPassagesAndQueriesPreserveLanguageAndResults() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let row = SessionRecord(id: "record", title: "Record", date: Date(timeIntervalSince1970: 0),
                                transcript: "alpha secret", summary: "", segments: [TranscriptSegment(
                                    source: .you, text: "alpha secret", isFinal: true, start: 0, end: 1, language: "de")])
        try await index.sync([row])
        let languages = await embedder.languages; XCTAssertEqual(languages, ["de"])
        let search = await index.search("meaning", in: [row]); XCTAssertEqual(search.map(\.id), [row.id])
        XCTAssertTrue(search.allSatisfy { $0.isRelated && !$0.matchesWords })
        let passages = await index.retrieve("meaning", in: [row]); XCTAssertEqual(passages.map(\.text), ["alpha secret"])
    }

    func testDeletionDuringHeldEmbeddingNeverRestoresVectorsOrText() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let row = record(); await embedder.hold(text: row.transcript)
        let pending = Task { try await index.update(row) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        try await index.remove(id: row.id); await embedder.release()
        let published = try await pending.value; XCTAssertFalse(published)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(directory).path))
        let ids = try await index.indexedIDs(); XCTAssertTrue(ids.isEmpty)
        let text = await index.search("secret", in: [row]); XCTAssertTrue(text.isEmpty)
        let all = await index.search("", in: [row]); XCTAssertTrue(all.isEmpty)
        let passages = await index.retrieve("secret", in: [row]); XCTAssertTrue(passages.isEmpty)
    }

    func testClearDuringHeldEmbeddingRejectsOldRecordButAllowsNewRecord() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let row = record(); await embedder.hold(text: row.transcript)
        let pending = Task { try await index.update(row) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        try await index.removeAll(); await embedder.release()
        let published = try await pending.value; XCTAssertFalse(published)
        let again = try await index.update(row); XCTAssertFalse(again)
        let fresh = record("fresh", text: "beta new"); try await index.update(fresh)
        let ids = try await index.indexedIDs(); XCTAssertEqual(ids, ["fresh"])
        let result = await index.search("secret", in: [row]); XCTAssertTrue(result.isEmpty)
    }

    func testCancellationDuringSecondPassagePublishesNoPartialRecord() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let row = record(text: "alpha secret", summary: "beta summary")
        XCTAssertEqual(HistoryChunker.chunks(for: row).count, 2)
        await embedder.hold(text: row.transcript)
        let pending = Task { try await index.update(row) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        pending.cancel(); await embedder.release()
        let published = try await pending.value; XCTAssertFalse(published)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(directory).path))
        let ids = try await index.indexedIDs(); XCTAssertTrue(ids.isEmpty)
        let retry = try await index.update(row); XCTAssertTrue(retry)
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: file(directory))))
        XCTAssertEqual(stored.chunks.count, 2)
    }

    func testNewerUpdateWinsOverHeldOlderUpdate() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let old = record(); let newer = record(text: "beta replacement")
        await embedder.hold(text: old.transcript)
        let pending = Task { try await index.update(old) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        let saved = try await index.update(newer); XCTAssertTrue(saved)
        await embedder.release(); let stale = try await pending.value; XCTAssertFalse(stale)
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: file(directory))))
        XCTAssertEqual(stored.fingerprint, HistoryChunker.fingerprint(HistoryChunker.chunks(for: newer), salt: embedder.signature))
        let passages = await index.retrieve("beta", in: [newer]); XCTAssertEqual(passages.map(\.text), [newer.transcript])
    }

    func testRebuildSupersedesHeldSync() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let old = record(); let current = record("fresh", text: "beta replacement")
        await embedder.hold(text: old.transcript)
        let pending = Task { try await index.sync([old]) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        let rebuilt = try await index.rebuild([current]); XCTAssertEqual(rebuilt.embedded, 1)
        await embedder.release(); let stale = try await pending.value; XCTAssertEqual(stale.embedded, 0)
        let ids = try await index.indexedIDs(); XCTAssertEqual(ids, ["fresh"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(directory).path))
    }

    func testDeletionAndClearDuringHeldQueriesReturnNoText() async throws {
        for clear in [false, true] {
            let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
            let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
            let row = record(); try await index.update(row); await embedder.hold(query: true)
            let pending = Task { await index.search("secret", in: [row]) }
            guard await wait(embedder) else { await embedder.release(); _ = await pending.value; continue }
            if clear { try await index.removeAll() } else { try await index.remove(id: row.id) }
            await embedder.release(); let late = await pending.value; XCTAssertTrue(late.isEmpty)
            let other = record("fresh"); try await index.update(other); await embedder.hold(query: true)
            let retrieval = Task { await index.retrieve("secret", in: [other]) }
            guard await wait(embedder) else { await embedder.release(); _ = await retrieval.value; continue }
            if clear { try await index.removeAll() } else { try await index.remove(id: other.id) }
            await embedder.release(); let passages = await retrieval.value; XCTAssertTrue(passages.isEmpty)
        }
    }

    func testCancelledHeldQueriesReturnNoResults() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let row = record(); try await index.update(row); await embedder.hold(query: true)
        let pending = Task { await index.search("secret", in: [row]) }
        guard await wait(embedder) else { await embedder.release(); _ = await pending.value; return }
        pending.cancel(); await embedder.release(); let search = await pending.value; XCTAssertTrue(search.isEmpty)
        await embedder.hold(query: true)
        let retrieval = Task { await index.retrieve("secret", in: [row]) }
        guard await wait(embedder) else { await embedder.release(); _ = await retrieval.value; return }
        retrieval.cancel(); await embedder.release(); let passages = await retrieval.value; XCTAssertTrue(passages.isEmpty)
    }
    func testBackendReplacementRejectsHeldOldInference() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let old = SuspendedHistoryEmbedder(); let replacement = SuspendedHistoryEmbedder(signature: "async-new-v1")
        let index = HistoryIndex(directory: directory, embedder: old); let row = record()
        await old.hold(text: row.transcript)
        let pending = Task { try await index.update(row) }
        guard await wait(old) else { await old.release(); _ = try await pending.value; return }
        try await index.setEmbedder(replacement)
        try await index.sync([row])
        await old.release(); let stale = try await pending.value; XCTAssertFalse(stale)
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: file(directory))))
        XCTAssertEqual(Set(stored.chunks.map(\.model)), [replacement.signature])
        let passages = await index.retrieve("meaning", in: [row]); XCTAssertEqual(passages.map(\.text), [row.transcript])
    }

    func testSameBackendIsNoOpAndFailedReplacementKeepsOldBackend() async throws {
        let directory = root(); let moved = directory.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: moved) }
        let old = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: old)
        let row = record(); try await index.update(row)
        let original = try Data(contentsOf: file(directory))
        try await index.setEmbedder(SuspendedHistoryEmbedder())
        XCTAssertEqual(try Data(contentsOf: file(directory)), original, "Identical backend must not wipe derived files")
        try FileManager.default.moveItem(at: directory, to: moved)
        try Data("not a directory".utf8).write(to: directory)
        do {
            try await index.setEmbedder(SuspendedHistoryEmbedder(signature: "async-new-v1"))
            XCTFail("Storage obstruction must not report a successful switch")
        } catch { }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: moved, to: directory)
        let result = await index.search("meaning", in: [row])
        XCTAssertEqual(result.map(\.id), [row.id], "Failure retains the prior backend after storage is restored")
    }

    func testOlderSyncCannotOverwriteLaterSaveForUnvisitedRecord() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let first = record("first", text: "alpha held")
        let old = record("later", text: "alpha old snapshot")
        let newer = record("later", text: "beta newer save")
        await embedder.hold(text: first.transcript)
        let pending = Task { try await index.sync([first, old]) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        try await index.update(newer)
        await embedder.release(); _ = try await pending.value
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: file(directory, id: newer.id))))
        XCTAssertEqual(stored.fingerprint, HistoryChunker.fingerprint(HistoryChunker.chunks(for: newer), salt: embedder.signature))
        let passages = await index.retrieve("meaning beta", in: [newer])
        XCTAssertEqual(passages.map(\.text), [newer.transcript])
    }

    func testOverlappingSyncSnapshotsKeepNewerArchive() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let first = record("first", text: "alpha held")
        let old = record("later", text: "alpha old snapshot")
        let newFirst = record("first", text: "beta updated first")
        let newer = record("later", text: "beta updated later")
        await embedder.hold(text: first.transcript)
        let pending = Task { try await index.sync([first, old]) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        try await index.sync([newFirst, newer])
        await embedder.release(); _ = try await pending.value
        for row in [newFirst, newer] {
            let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: file(directory, id: row.id))))
            XCTAssertEqual(stored.fingerprint, HistoryChunker.fingerprint(HistoryChunker.chunks(for: row), salt: embedder.signature))
        }
        let passages = await index.retrieve("meaning beta", in: [newFirst, newer])
        XCTAssertEqual(Set(passages.map(\.text)), [newFirst.transcript, newer.transcript])
    }

    func testClearAlsoRevokesUnvisitedSnapshotRecords() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let embedder = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: embedder)
        let first = record("first", text: "alpha held")
        let later = record("later", text: "beta unvisited")
        await embedder.hold(text: first.transcript)
        let pending = Task { try await index.sync([first, later]) }
        guard await wait(embedder) else { await embedder.release(); _ = try await pending.value; return }
        try await index.removeAll(); await embedder.release(); _ = try await pending.value
        try await index.sync([first, later])
        let ids = try await index.indexedIDs(); XCTAssertTrue(ids.isEmpty)
        let result = await index.search("unvisited", in: [later]); XCTAssertTrue(result.isEmpty)
    }

    func testCancelledBackendSelectionLeavesCurrentBackendAndRecordsUntouched() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let old = SuspendedHistoryEmbedder(); let index = HistoryIndex(directory: directory, embedder: old)
        let row = record(); try await index.update(row)
        let original = try Data(contentsOf: file(directory))
        let selection = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await index.setEmbedder(SuspendedHistoryEmbedder(signature: "cancelled-backend"))
                return false
            } catch is CancellationError { return true } catch { return false }
        }
        let cancelled = await selection.value; XCTAssertTrue(cancelled)
        XCTAssertEqual(try? Data(contentsOf: file(directory)), original)
        let found = await index.search("meaning", in: [row]); XCTAssertEqual(found.map(\.id), [row.id])
    }

}
