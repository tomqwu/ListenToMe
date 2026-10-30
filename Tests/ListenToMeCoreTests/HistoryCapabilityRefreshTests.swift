import XCTest
@testable import ListenToMeCore

private actor RefreshEmbedder: HistoryEmbedder {
    nonisolated let signature = "refresh-fixture-v1"
    let available: Bool
    private(set) var calls = 0
    private var held = false
    private var waiter: CheckedContinuation<Void, Never>?
    init(_ available: Bool) { self.available = available }
    func hold() { held = true }
    func waiting() -> Bool { waiter != nil }
    func release() { held = false; let old = waiter; waiter = nil; old?.resume() }
    func embed(_ text: String) async -> HistoryVector? {
        calls += 1
        if held { await withCheckedContinuation { waiter = $0 } }
        return available ? HistoryVector(model: signature, values: [1, 0]) : nil
    }
    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        available && models.contains(signature) ? [HistoryVector(model: signature, values: [1, 0])] : []
    }
}

@MainActor
final class HistoryCapabilityRefreshTests: XCTestCase {
    private func row() -> SessionRecord {
        SessionRecord(id: "one", title: "Owned fixture", date: Date(timeIntervalSince1970: 0),
                      transcript: "airline aircraft airport terminal", summary: "")
    }
    func testExplicitRefreshReembedsUnchangedNilCacheWithEqualRecipe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = row(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(record)
        let absent = RefreshEmbedder(false); let ready = RefreshEmbedder(true)
        let index = HistoryIndex(directory: root, embedder: absent)
        try await index.sync([record])
        let file = root.appendingPathComponent("one.vectors"); let before = try Data(contentsOf: file)
        try await index.setEmbedder(ready, forceRefresh: true)
        let report = try await index.sync([record])
        XCTAssertEqual(report.embedded, 1)
        let calls = await ready.calls; XCTAssertEqual(calls, 1)
        XCTAssertNotEqual(try Data(contentsOf: file), before)
        let result = await index.search("meaning", in: [record]); XCTAssertEqual(result.map(\.id), [record.id])
        XCTAssertTrue(result.first?.isRelated == true)
        XCTAssertEqual(try encoder.encode(record), original)
    }
    func testOrdinarySameRecipeSyncStillReusesStoredPassages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = RefreshEmbedder(true); let unused = RefreshEmbedder(true)
        let index = HistoryIndex(directory: root, embedder: original); try await index.sync([row()])
        let file = root.appendingPathComponent("one.vectors"); let bytes = try Data(contentsOf: file)
        try await index.setEmbedder(unused); let report = try await index.sync([row()])
        let calls = await unused.calls; XCTAssertEqual(calls, 0); XCTAssertEqual(report.unchanged, 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testDeletionDuringHeldExplicitRefreshCannotRestoreRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = RefreshEmbedder(false); let fresh = RefreshEmbedder(true)
        let index = HistoryIndex(directory: root, embedder: original); let record = row()
        try await index.sync([record]); await fresh.hold()
        try await index.setEmbedder(fresh, forceRefresh: true)
        let task = Task { try await index.sync([record]) }
        for _ in 0..<150 { if await fresh.waiting() { break }; try await Task.sleep(for: .milliseconds(10)) }
        let waiting = await fresh.waiting()
        guard waiting else {
            await fresh.release(); _ = try await task.value
            XCTFail("Fresh inference never started"); return
        }
        try await index.remove(id: record.id); await fresh.release(); _ = try await task.value
        let ids = try await index.indexedIDs(); XCTAssertTrue(ids.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("one.vectors").path))
    }
}
