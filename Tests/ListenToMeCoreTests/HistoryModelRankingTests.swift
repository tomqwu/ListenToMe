import XCTest
@testable import ListenToMeCore

/// Controlled vectors demonstrate a population boundary, not MPNet calibration or language quality.
private struct SeparateGroupEmbedder: HistoryEmbedder {
    static let apple = "w:en:1"
    static let optional = "optional-fixture:1"
    let signature = "independent-populations-test-v1"
    let optionalScore: Float

    // This extra method compiles before the proposed protocol hook exists. Existing production
    // code ignores it; the observable membership tests must fail before grouping is implemented.
    nonisolated func relevanceGroup(for model: String) -> String {
        model == Self.optional ? "optional-fixture" : "legacy"
    }
    func embed(_ text: String) -> HistoryVector? {
        if text.hasPrefix("Optional") { return vector(Self.optional, score: optionalScore) }
        return vector(Self.apple, score: text.hasPrefix("Apple target") ? 0.75 : 0)
    }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] {
        models.sorted().map { HistoryVector(model: $0, values: [1, 0]) }
    }
    private func vector(_ model: String, score: Float) -> HistoryVector {
        HistoryVector(model: model, values: [score, (1 - score * score).squareRoot()])
    }
}

/// No grouping hook at all: adding that hook must retain the default for old conformers.
private struct LegacyLanguageEmbedder: HistoryEmbedder {
    let signature = "legacy-language-population-test-v1"
    func embed(_ text: String) -> HistoryVector? {
        let model = text.hasPrefix("French") ? "w:fr:1" : "w:en:1"
        let score: Float = text.hasPrefix("French") ? 0.98 : (text.hasPrefix("Apple target") ? 0.75 : 0)
        return HistoryVector(model: model, values: [score, (1 - score * score).squareRoot()])
    }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] {
        models.sorted().map { HistoryVector(model: $0, values: [1, 0]) }
    }
}

final class HistoryModelRankingTests: XCTestCase {
    private let query = "meaning"
    private func record(_ id: String, _ text: String) -> SessionRecord {
        SessionRecord(id: id, title: id, date: Date(timeIntervalSince1970: 0), transcript: text, summary: "")
    }
    private var appleRecords: [SessionRecord] {
        [record("apple-target", "Apple target about library repairs")]
            + (0..<4).map { record("apple-noise-\($0)", "Apple unrelated noise \($0)") }
    }
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testOptionalTopScoreCannotDemoteEligibleLegacyResults() async throws {
        // Population mean remains low; the existing failure is specifically the other group's top margin.
        try await checkBoundary(optionalScore: 0.98, optionalCount: 1)
    }

    func testOptionalPopulationCannotChangeLegacyRelevanceMean() async throws {
        // Apple remains the overall top. Only the unrelated group's many scores erase Apple's mean gap.
        try await checkBoundary(optionalScore: 0.74, optionalCount: 40)
    }

    private func checkBoundary(optionalScore: Float, optionalCount: Int) async throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let index = HistoryIndex(directory: folder, embedder: SeparateGroupEmbedder(optionalScore: optionalScore))
        let original = appleRecords
        XCTAssertTrue(SessionSearch.search(original, query: query).isEmpty, "No keyword credit in the invariant")
        try await index.sync(original)
        let beforeRelated = await index.search(query, in: original).filter(\.isRelated).map(\.id)
        let beforeAsk = await index.retrieve(query, in: original)
        XCTAssertEqual(beforeRelated, ["apple-target"], "Establish actual legacy eligibility before extending the archive")
        XCTAssertEqual(beforeAsk.map(\.recordID), ["apple-target"])
        let additional = (0..<optionalCount).map { record("optional-\($0)", "Optional unrelated conversation \($0)") }
        let extended = original + additional
        XCTAssertTrue(SessionSearch.search(extended, query: query).isEmpty)
        try await index.sync(extended)
        let afterRelated = await index.search(query, in: extended).filter {
            $0.id.hasPrefix("apple-") && $0.isRelated
        }.map(\.id)
        let afterAsk = await index.retrieve(query, in: extended).filter { $0.recordID.hasPrefix("apple-") }
        XCTAssertEqual(afterRelated, beforeRelated, "Raw scores from another relevance group must not demote Apple membership")
        XCTAssertEqual(afterAsk.map(\.id), beforeAsk.map(\.id), "Existing Apple Ask membership must survive the unrelated group's statistics")
        XCTAssertEqual(afterAsk.map(\.text), beforeAsk.map(\.text))
        XCTAssertEqual(afterAsk.map(\.source), beforeAsk.map(\.source))
    }

    func testExistingAppleModelTagsKeepLegacyPopulationBehavior() async throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let index = HistoryIndex(directory: folder, embedder: LegacyLanguageEmbedder())
        let original = appleRecords
        try await index.sync(original)
        let before = await index.search(query, in: original).filter(\.isRelated).map(\.id)
        XCTAssertEqual(before, ["apple-target"])
        let extended = original + [record("legacy-french", "French legacy passage")]
        try await index.sync(extended)
        let after = await index.search(query, in: extended).filter(\.isRelated).map(\.id)
        let passages = await index.retrieve(query, in: extended)
        XCTAssertEqual(after, ["legacy-french"], "All undeclared model tags still share legacy top-margin behavior")
        XCTAssertEqual(passages.map(\.recordID), ["legacy-french"])
    }
    func testIndependentGroupScoreScalesCannotChangeFusedOrder() async throws {
        var relatedOrders: [[String]] = []
        var askOrders: [[String]] = []
        let expected: Set<String> = ["apple-target", "optional-0"]
        for score: Float in [0.98, 0.56] {
            let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
            let index = HistoryIndex(directory: folder, embedder: SeparateGroupEmbedder(optionalScore: score))
            let records = appleRecords + [record("optional-0", "Optional unrelated conversation 0")]
            XCTAssertTrue(SessionSearch.search(records, query: query).isEmpty)
            // Each group's first candidate qualifies independently; the optional singleton's
            // two scales both exceed the existing small-sample floor, with no parameter changes.
            try await index.sync(records)
            let related = await index.search(query, in: records).filter(\.isRelated).map(\.id)
            let passages = await index.retrieve(query, in: records).map(\.recordID)
            XCTAssertEqual(Set(related), expected, "Both independently admitted groups remain represented")
            XCTAssertEqual(Set(passages), expected, "Ask cap is nonbinding for these two passages")
            relatedOrders.append(related); askOrders.append(passages)
        }
        XCTAssertEqual(relatedOrders[0], relatedOrders[1], "Incomparable raw scales cannot order independent groups")
        XCTAssertEqual(askOrders[0], askOrders[1], "Ask combines admitted group ranks, not raw cosine magnitudes")
    }

    func testTiedMultiGroupPassagesHaveDeterministicOrderWithoutChangingLegacyTies() async throws {
        let first = record("apple-a", "Apple target first passage")
        let second = record("apple-b", "Apple target second passage")
        let optional = record("optional-0", "Optional unrelated conversation 0")
        var searches: [[String]] = []; var passages: [[String]] = []
        for tied in [[first, second], [second, first]] {
            let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
            let index = HistoryIndex(directory: folder, embedder: SeparateGroupEmbedder(optionalScore: 0.98))
            let records = tied + [optional]
            try await index.sync(records)
            let search = await index.search(query, in: records).filter(\.isRelated).map(\.id)
            let ask = await index.retrieve(query, in: records).map(\.recordID)
            XCTAssertEqual(Set(search), Set(records.map(\.id)))
            XCTAssertEqual(Set(ask), Set(records.map(\.id)))
            searches.append(search); passages.append(ask)
        }
        XCTAssertEqual(searches[0], searches[1])
        XCTAssertEqual(passages[0], passages[1], "A group-local tie cannot assign ranks from incidental archive order")
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = HistoryIndex(directory: folder, embedder: LegacyLanguageEmbedder())
        try await legacy.sync([second, first])
        let originalOrder = await legacy.retrieve(query, in: [second, first]).map(\.recordID)
        XCTAssertEqual(originalOrder, [second.id, first.id], "The existing single-group raw-sort path is preserved")
    }

}
