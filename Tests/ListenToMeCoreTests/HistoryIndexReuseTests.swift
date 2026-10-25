import Foundation
import XCTest
@testable import ListenToMeCore

final class HistoryIndexReuseTests: XCTestCase {
    private final class Counter: HistoryEmbedder, @unchecked Sendable {
        let signature: String
        private let lock = NSLock()
        private var calls: [String] = []
        let available: Bool
        init(signature: String = "count-v1", available: Bool = true) {
            self.signature = signature; self.available = available
        }
        var count: Int { lock.withLock { calls.count } }
        func embed(_ text: String) -> HistoryVector? { embed(text, transcribedIn: "unknown") }
        func embed(_ text: String, transcribedIn language: String) -> HistoryVector? {
            lock.withLock { calls.append(language + text) }
            return available ? HistoryVector(model: "test", values: [1, 0]) : nil
        }
        func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
    }

    private func record(summary: String = "", first: String = "budget", language: String = "en") -> SessionRecord {
        let texts = [first, "travel", "legal"].map { String(repeating: $0 + " ", count: 55) }
        return SessionRecord(id: "conversation", title: "Test", date: Date(timeIntervalSince1970: 0),
                             transcript: texts.joined(separator: "\n"), summary: summary,
                             segments: texts.map { TranscriptSegment(source: .you, text: $0, isFinal: true, start: 0, end: 1,
                                                                     language: language) })
    }

    func testSummaryInsertionAndSinglePassageEditReuseVectorsAfterReopeningWithoutMemoryCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter()
        let original = record()
        let count = HistoryChunker.chunks(for: original).count
        let index = HistoryIndex(directory: directory, embedder: counter, memoryBudget: 0)
        try await index.update(original)
        XCTAssertEqual(counter.count, count)
        let reopened = HistoryIndex(directory: directory, embedder: counter, memoryBudget: 0)
        let withSummary = record(summary: "A new summary")
        try await reopened.update(withSummary)
        XCTAssertEqual(counter.count, count + 1, "Inserting a summary shifts ordinals without re-embedding speech")
        try await reopened.update(record(summary: "A new summary", first: "money"))
        XCTAssertEqual(counter.count, count + 2, "Only the changed passage needs an embedding")
        let data = try Data(contentsOf: directory.appendingPathComponent("conversation.vectors"))
        let stored = try XCTUnwrap(HistoryIndexFile.decode(data))
        XCTAssertEqual(stored.chunks.map(\.ordinal), Array(0..<stored.chunks.count))
        try await reopened.remove(id: "conversation")
        try await reopened.update(withSummary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("conversation.vectors").path))
    }

    func testLanguageAndEmbeddingMethodChangesInvalidateReusablePassages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter()
        let index = HistoryIndex(directory: directory, embedder: counter)
        let original = record()
        let count = HistoryChunker.chunks(for: original).count
        try await index.update(original)
        try await index.update(record(language: "fr"))
        XCTAssertEqual(counter.count, count * 2)
        let replacement = Counter(signature: "count-v2")
        let changedMethod = HistoryIndex(directory: directory, embedder: replacement)
        try await changedMethod.update(record(language: "fr"))
        XCTAssertEqual(replacement.count, count)
    }
    func testAppendingToLongConversationEmbedsOnlyNewPassagesAndDuplicatePassagesShareWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter()
        let index = HistoryIndex(directory: directory, embedder: counter, memoryBudget: 0)
        let lines = (0..<120).map { "Passage \($0) " + String(repeating: "budget ", count: 45) }
        func conversation(_ text: String) -> SessionRecord {
            SessionRecord(id: "long", title: "Long", date: Date(timeIntervalSince1970: 0),
                          transcript: text, summary: "")
        }
        let original = conversation(lines.joined(separator: "\n"))
        XCTAssertEqual(HistoryChunker.chunks(for: original).count, 120)
        try await index.update(original)
        XCTAssertEqual(counter.count, 120)
        let newLine = "A new passage " + String(repeating: "travel ", count: 45)
        let extended = conversation((lines + [newLine, newLine]).joined(separator: "\n"))
        try await index.update(extended)
        XCTAssertEqual(counter.count, 121, "Unchanged and duplicate passages do not repeat embedding work")
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf:
            directory.appendingPathComponent("long.vectors"))))
        XCTAssertEqual(stored.chunks.count, 122, "Both duplicate positions remain searchable")
        XCTAssertEqual(stored.chunks.suffix(2).map(\.ordinal), [120, 121])
    }

    func testUnavailableDuplicatePassagesAreAttemptedOncePerChangedSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter(available: false)
        let index = HistoryIndex(directory: directory, embedder: counter)
        let line = String(repeating: "unsupported passage ", count: 25)
        func conversation(summary: String) -> SessionRecord {
            SessionRecord(id: "unsupported", title: "Test", date: Date(timeIntervalSince1970: 0),
                          transcript: [line, line, line].joined(separator: "\n"), summary: summary)
        }
        let original = conversation(summary: "")
        XCTAssertEqual(HistoryChunker.chunks(for: original).count, 3)
        try await index.update(original)
        XCTAssertEqual(counter.count, 1)
        try await index.update(conversation(summary: "New summary"))
        XCTAssertEqual(counter.count, 3, "Unavailable passages retry on a changed save, once per distinct passage")
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf:
            directory.appendingPathComponent("unsupported.vectors"))))
        XCTAssertTrue(stored.chunks.isEmpty, "Unavailable passages must not create searchable vectors")
    }

}
