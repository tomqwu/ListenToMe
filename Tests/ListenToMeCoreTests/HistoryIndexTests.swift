import XCTest
@testable import ListenToMeCore

/// A deterministic stand-in for NaturalLanguage: each dimension is a topic, and a passage's vector
/// counts its topic words. German text has "no model", like a language without an on-device
/// embedding, so the keyword fallback can be tested on every machine.
struct TopicEmbedder: HistoryEmbedder {
    static let model = "fake:en:1"
    static let topics: [[String]] = [
        ["budget", "money", "funding", "dollars", "finance", "spend"],
        ["flight", "airport", "hotel", "trip", "travel", "passport"],
        ["lunch", "dinner", "pizza", "restaurant", "food"],
        ["contract", "lawyer", "attorney", "clause", "agreement"]
    ]
    static let germanWords: Set<String> = ["der", "die", "das", "und", "wurde", "ist"]
    var signature = "topics-v1"

    func embed(_ text: String) -> HistoryVector? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        if words.contains(where: Self.germanWords.contains) { return nil }
        var values = Self.topics.map { topic in Float(words.filter(topic.contains).count) }
        values.append(0.05)
        return HistoryVector(model: Self.model, values: values)
    }

    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] {
        guard models.contains(Self.model), let vector = embed(query) else { return [] }
        return [vector]
    }
}

final class HistoryIndexTests: XCTestCase {
    private var root: URL!
    private let base = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryIndexTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func index(_ embedder: any HistoryEmbedder = TopicEmbedder(), budget: Int = 32 << 20) -> HistoryIndex {
        HistoryIndex(directory: HistoryIndex.directory(besideArchive: root.appendingPathComponent("Conversations")),
                     embedder: embedder, memoryBudget: budget)
    }

    private func record(_ id: String, _ transcript: String, title: String = "", summary: String = "",
                        notes: String? = nil, age: TimeInterval = 0) -> SessionRecord {
        let segments = transcript.split(separator: "\n").enumerated().map { offset, line in
            TranscriptSegment(source: offset.isMultiple(of: 2) ? .you : .others, text: String(line), isFinal: true,
                              start: Double(offset), end: Double(offset) + 1)
        }
        return SessionRecord(id: id, title: title.isEmpty ? id : title, date: base.addingTimeInterval(-age),
                             transcript: transcript, summary: summary, segments: segments, notes: notes)
    }

    /// Four conversations, each about one topic, none sharing the query words used below.
    private var corpus: [SessionRecord] {
        [
            record("budget", "We reviewed the quarterly budget and the funding round.\nFinance wants less spend.", age: 40),
            record("travel", "Book the flight and the hotel for Berlin.\nDana handles the passport forms.", age: 30),
            record("lunch", "The team lunch was great.\nNext time we try the pizza restaurant.", age: 20),
            record("legal", "The lawyer flagged the liability clause in the contract.", age: 10)
        ]
    }

    // MARK: - Ranking

    func testMeaningFindsAConversationThatSharesNoWordWithTheQuery() async throws {
        let index = index()
        try await index.sync(corpus)
        let results = await index.search("money", in: corpus)
        XCTAssertEqual(results.first?.id, "budget")
        XCTAssertEqual(results.first?.isRelated, true)
        XCTAssertEqual(results.first?.matchesWords, false, "No conversation contains the word 'money'")
        XCTAssertEqual(results.first?.snippet?.source, .transcript)
        XCTAssertTrue(results.first?.snippet?.text.contains("budget") == true)
        XCTAssertFalse(results.contains { $0.id == "lunch" }, "Unrelated topics stay out")
    }

    func testAConversationFoundBothWaysOutranksAKeywordOnlyMatch() async throws {
        // Both mention "airport"; only "plan" is about travel. The newer "note" wins on keywords alone.
        let wordOnly = record("note", "Pizza and dinner at the airport restaurant, great food.", age: 0)
        let both = record("plan", "Plan the airport pickup.\nBook the flight and hotel.", age: 50)
        let records = corpus + [wordOnly, both]
        XCTAssertEqual(SessionSearch.search(records, query: "airport").map(\.id), ["note", "plan"])
        let index = index()
        try await index.sync(records)
        let results = await index.search("airport", in: records)
        XCTAssertEqual(results.first?.id, "plan")
        XCTAssertEqual(results.first?.matchesWords, true)
        XCTAssertEqual(results.first?.isRelated, true)
        let note = try XCTUnwrap(results.first { $0.id == "note" })
        XCTAssertTrue(note.matchesWords && !note.isRelated, "Every keyword match is kept")
        XCTAssertTrue(results.contains { $0.id == "travel" && $0.isRelated && !$0.matchesWords })
        XCTAssertFalse(results.contains { $0.id == "budget" })
    }

    func testRelatedResultsAreBoundedAndNeedTheFloor() {
        let params = HistoryRanking.Parameters(floor: 0.5, margin: 0.1, maxRelated: 2)
        let picked = HistoryRanking.related([("a", 0.9), ("b", 0.85), ("c", 0.79), ("d", 0.4)], parameters: params)
        XCTAssertEqual(picked.map(\.id), ["a", "b"], "Within the margin of the best and above the floor")
        XCTAssertTrue(HistoryRanking.related([("a", 0.3)], parameters: params).isEmpty)
        XCTAssertTrue(HistoryRanking.related([], parameters: params).isEmpty)
    }

    func testFusionPrefersBothThenKeywordOrder() {
        let order = HistoryRanking.fuse(keyword: ["k1", "both", "k2"], semantic: ["s1", "both"], fusion: 60)
        XCTAssertEqual(order.first, "both")
        XCTAssertEqual(order, ["both", "k1", "s1", "k2"], "A tie goes to the keyword match")
        XCTAssertEqual(HistoryRanking.fuse(keyword: [], semantic: ["b", "a"], fusion: 60), ["b", "a"])
        XCTAssertEqual(HistoryRanking.fuse(keyword: ["x", "y"], semantic: [], fusion: 60), ["x", "y"])
    }

    func testSemanticOnlyResultsAreCappedButKeywordMatchesAreNot() async throws {
        let records = (0..<5).map { record("trip\($0)", "Book the flight and the hotel.", age: Double($0)) }
        let index = HistoryIndex(directory: root.appendingPathComponent("capped"), embedder: TopicEmbedder(),
                                 parameters: .init(maxRelated: 2))
        try await index.sync(records)
        let value101 = await index.search("airport", in: records).count
        XCTAssertEqual(value101, 2)
        let value102 = await index.search("flight", in: records).count
        XCTAssertEqual(value102, 5)
    }

    // MARK: - Empty index and language fallback

    func testAnEmptyIndexIsTheKeywordSearch() async throws {
        let index = index()
        let results = await index.search("pizza", in: corpus)   // nothing synced yet
        XCTAssertEqual(results.map(\.id), ["lunch"])
        XCTAssertEqual(results.first?.matchesWords, true)
        XCTAssertEqual(results.first?.isRelated, false)
        XCTAssertTrue(results.first?.snippet?.text.contains("pizza") == true)
        let empty = await index.search("pizza", in: [])
        XCTAssertTrue(empty.isEmpty)
        let none = await index.search("money", in: corpus)
        XCTAssertTrue(none.isEmpty, "Without vectors a word that appears nowhere finds nothing")
        let all = await index.search("  ", in: corpus)
        XCTAssertEqual(all.map(\.id), ["legal", "lunch", "travel", "budget"], "No query lists everything, newest first")
        let retrieved = await index.retrieve("Where did we eat pizza?", in: corpus)
        XCTAssertEqual(retrieved.map(\.recordID), ["lunch"], "Questions still retrieve by their words")
    }

    func testALanguageWithoutAModelFallsBackToKeywords() async throws {
        let german = record("de", "Der Haushalt wurde besprochen und die Kosten sind zu hoch.")
        let records = corpus + [german]
        let index = index()
        try await index.sync(records)
        let value1 = try await index.indexedIDs().contains("de")
        XCTAssertTrue(value1, "Indexed, with no vectors")
        let byWord = await index.search("Haushalt", in: records)
        XCTAssertEqual(byWord.map(\.id), ["de"])
        XCTAssertEqual(byWord.first?.isRelated, false)
        let byMeaning = await index.search("money", in: records)
        XCTAssertFalse(byMeaning.contains { $0.id == "de" })
        XCTAssertEqual(byMeaning.first?.id, "budget", "Other languages keep semantic ranking")
    }

    func testAnEmbedderWithNoModelsAtAllLeavesKeywordSearch() async throws {
        struct Nothing: HistoryEmbedder {
            var signature = "none"
            func embed(_ text: String) -> HistoryVector? { nil }
            func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
        }
        let index = index(Nothing())
        try await index.sync(corpus)
        let results = await index.search("budget", in: corpus)
        XCTAssertEqual(results.map(\.id), SessionSearch.search(corpus, query: "budget").map(\.id))
    }

    // MARK: - Incremental sync, deletion, rebuild

    func testSyncIsIncrementalAndStoredOutsideBackups() async throws {
        let index = index()
        let first = try await index.sync(corpus)
        XCTAssertEqual(first, HistoryIndexReport(embedded: 4))
        let again = try await index.sync(corpus)
        XCTAssertEqual(again, HistoryIndexReport(unchanged: 4))
        var edited = corpus
        edited[2] = record("lunch", "We booked the flight.", age: 20)
        let value2 = try await index.sync(edited)
        XCTAssertEqual(value2, HistoryIndexReport(embedded: 1, unchanged: 3))
        let moved = await index.search("airport", in: edited)
        XCTAssertTrue(moved.contains { $0.id == "lunch" && $0.isRelated }, "New text, new vectors")
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(index.directory))
        XCTAssertEqual(index.directory.lastPathComponent, "Search Index")
        XCTAssertEqual(index.directory.deletingLastPathComponent().standardizedFileURL.path,
                       root.standardizedFileURL.path, "Beside the archive")
    }

    func testUpdateEmbedsOneSavedConversationAndLeavesTheRest() async throws {
        let index = index()
        try await index.sync(Array(corpus.prefix(2)))
        let added = try await index.update(corpus[2])
        XCTAssertTrue(added)
        let again = try await index.update(corpus[2])
        XCTAssertFalse(again, "Unchanged text is not embedded twice")
        let invalid = try await index.update(record("no/slash", "The budget."))
        XCTAssertFalse(invalid)
        let ids = try await index.indexedIDs()
        XCTAssertEqual(ids, ["budget", "travel", "lunch"])
    }

    func testStaleVectorsAreNotTrustedUntilTheNextSync() async throws {
        let index = index()
        try await index.sync(corpus)
        var edited = corpus
        edited[0] = record("budget", "We talked about the weather.", age: 40)
        let results = await index.search("money", in: edited)
        XCTAssertFalse(results.contains { $0.id == "budget" }, "Vectors of old text must not surface new text")
        let passages = await index.retrieve("money", in: edited)
        XCTAssertTrue(passages.isEmpty)
    }

    func testDeletingAConversationRemovesItsVectors() async throws {
        let index = index()
        try await index.sync(corpus)
        try await index.remove(id: "budget")
        var ids = try await index.indexedIDs()
        XCTAssertFalse(ids.contains("budget"))
        let file = index.directory.appendingPathComponent("budget.vectors")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let value103 = await index.search("money", in: corpus).isEmpty
        XCTAssertTrue(value103, "Its meaning is gone with it")
        try await index.remove(id: "../escape")   // never a path outside the folder
        // A conversation missing from the archive loses its vectors on the next sync.
        let report = try await index.sync(Array(corpus.dropFirst(2)))
        XCTAssertEqual(report.removed, 1)
        ids = try await index.indexedIDs()
        XCTAssertEqual(ids, ["lunch", "legal"])
    }

    func testClearHistoryRemovesEveryVector() async throws {
        let index = index()
        try await index.sync(corpus)
        try await index.removeAll()
        let value3 = try await index.indexedIDs().isEmpty
        XCTAssertTrue(value3)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: index.directory.path)
        XCTAssertEqual(leftovers, ["index.json"])
        let value104 = await index.search("money", in: corpus).isEmpty
        XCTAssertTrue(value104)
    }

    func testRebuildRecoversFromDamageAndFromAnotherVersion() async throws {
        let first = index()
        try await first.sync(corpus)
        let file = first.directory.appendingPathComponent("travel.vectors")
        try Data("not an index file".utf8).write(to: file)
        // A fresh instance (next launch) reads the folder: the damaged file is dropped and re-embedded.
        let second = index()
        let value4 = try await second.indexedIDs().contains("travel")
        XCTAssertFalse(value4)
        let value5 = try await second.sync(corpus).embedded
        XCTAssertEqual(value5, 1)
        let value105 = await second.search("airport", in: corpus).first?.id
        XCTAssertEqual(value105, "travel")

        // A different embedding method invalidates every stored vector.
        let changed = index(TopicEmbedder(signature: "topics-v2"))
        let value6 = try await changed.indexedIDs().isEmpty
        XCTAssertTrue(value6)
        let value7 = try await changed.sync(corpus).embedded
        XCTAssertEqual(value7, 4)

        // An explicit rebuild embeds everything again.
        let value8 = try await changed.rebuild(corpus)
        XCTAssertEqual(value8, HistoryIndexReport(embedded: 4))
        let value106 = await changed.search("money", in: corpus).first?.id
        XCTAssertEqual(value106, "budget")
    }

    func testVectorsBeyondTheMemoryBudgetAreReadFromDisk() async throws {
        let index = index(budget: 0)
        try await index.sync(corpus)
        let value107 = await index.search("money", in: corpus).first?.id
        XCTAssertEqual(value107, "budget")
        let reopened = self.index(budget: 0)
        let value108 = await reopened.search("money", in: corpus).first?.id
        XCTAssertEqual(value108, "budget")
    }

    func testInvalidIDsAreSkipped() async throws {
        let index = index()
        let report = try await index.sync([record("bad/id", "The budget.")])
        XCTAssertEqual(report, HistoryIndexReport())
        XCTAssertFalse(HistoryIndex.isValidID(""))
    }

    func testCancelledSyncStopsBetweenConversations() async throws {
        let index = index()
        let records = corpus
        let task = Task { () -> HistoryIndexReport in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.sync(records)
        }
        let report = try await task.value
        XCTAssertEqual(report.embedded, 0)
    }

    // MARK: - Retrieval for "Ask your history"

    func testRetrievalByMeaningAloneKeepsOnlyPassagesCloseToTheBest() async throws {
        let records = [record("money", "The budget and the funding money."), record("mixed", "A budget trip.", age: 1)]
        let index = index()
        try await index.sync(records)
        // No question word appears in either; "mixed" is only half about money.
        let passages = await index.retrieve("Where did the dollars go?", in: records)
        XCTAssertEqual(passages.map(\.recordID), ["money"])
    }

    func testRetrieveReturnsTheBestPassagesWithAPerConversationCap() async throws {
        let long = record("long", (0..<12).map { "The budget line \($0) needs more funding and finance review." }
            .joined(separator: "\n"), age: 5)
        let records = corpus + [long]
        let index = index()
        try await index.sync(records)
        let passages = await index.retrieve("How much money is left?", in: records, limit: 4, perConversation: 2)
        XCTAssertLessThanOrEqual(passages.filter { $0.recordID == "long" }.count, 2)
        XCTAssertTrue(passages.contains { $0.recordID == "budget" })
        XCTAssertLessThanOrEqual(passages.count, 4)
        XCTAssertEqual(passages.first.map { $0.score >= passages.last!.score }, true)
        XCTAssertEqual(passages.first?.id, "\(passages.first!.recordID)#\(passages.first!.ordinal)")
    }
}
