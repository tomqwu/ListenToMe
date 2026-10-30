import Foundation
import NaturalLanguage
import XCTest
@testable import ListenToMeCore

/// Installed Apple vocabulary acceptance; missing prerequisites fail, never skip or download.
@MainActor
final class MacHistoryEmbeddingCaseTests: XCTestCase {
    private let travel = "Wir buchen Flüge und ein Hotel für die Konferenz in Berlin. "
        + "Dana kümmert sich um die Visumunterlagen und Formulare zur Reisekostenerstattung."

    private func germanWords() throws -> NLEmbedding {
        XCTAssertTrue(NLTagger.availableTagSchemes(for: .word, language: .german).contains(.lexicalClass),
                      "Install German lexical assets before this native acceptance suite")
        return try XCTUnwrap(NLEmbedding.wordEmbedding(for: .german),
                             "German Apple word model must already be installed")
    }

    func testGermanTravelUsesActualCaseSensitiveNounsAndCompatibleQueries() async throws {
        let model = try germanWords()
        let nouns = ["Flüge", "Hotel", "Konferenz", "Berlin", "Formulare"]
        let vectors = try nouns.map { try XCTUnwrap(model.vector(for: $0), "Missing original-case topic noun: \($0)") }
        var mean = [Double](repeating: 0, count: model.dimension)
        for vector in vectors {
            XCTAssertEqual(vector.count, model.dimension)
            for index in vector.indices { mean[index] += vector[index] / Double(vectors.count) }
        }
        let expected = HistoryVector(model: "w:de:\(model.revision)", values: mean.map(Float.init))
        let embedder = NaturalLanguageEmbedder()
        let explicit = await embedder.embed(travel, transcribedIn: "de-DE")
        let actual = try XCTUnwrap(explicit)
        XCTAssertEqual(actual.model, expected.model)
        XCTAssertEqual(actual.values.count, expected.values.count)
        XCTAssertTrue(actual.values.allSatisfy(\.isFinite))
        XCTAssertEqual(actual.values.reduce(Float(0)) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
        for (left, right) in zip(actual.values, expected.values) { XCTAssertEqual(left, right, accuracy: 0.000001) }
        let detected = await embedder.embed(travel)
        XCTAssertEqual(detected, actual)
        for query in ["Flughafen", "Reisepass"] {
            let queries = embedder.embedQuery(query, models: [actual.model])
            XCTAssertEqual(queries.count, 1, query)
            XCTAssertEqual(try XCTUnwrap(queries.first).model, actual.model)
            XCTAssertTrue(try XCTUnwrap(queries.first).values.allSatisfy(\.isFinite))
        }
    }

    func testGermanMinimumAndOriginalFillerRemainRejected() async throws {
        let model = try germanWords()
        for noun in ["Flüge", "Hotel"] { XCTAssertNotNil(model.vector(for: noun)) }
        let embedder = NaturalLanguageEmbedder()
        for text in ["Flüge und Hotel",
                     "Okay, ja. Also, äh, mal sehen. Richtig, richtig. Klingt gut für mich.",
                     "Kannst du mich hören? Ich glaube, du bist stummgeschaltet. Ja, jetzt höre ich dich."] {
            let result = await embedder.embed(text, transcribedIn: "de")
            XCTAssertNil(result, "The existing three-word minimum and original filler controls stay unchanged: \(text)")
        }
    }

    func testCaseRecipeUpgradeRebuildsEmptyVectorsAndPreservesArchive() async throws {
        _ = try germanWords()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppleWordCase-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(directory: root.appendingPathComponent("Conversations"))
        let record = SessionRecord(id: "german-travel", title: "Original travel",
                                   date: Date(timeIntervalSince1970: 123),
                                   transcript: travel, summary: "",
                                   segments: [TranscriptSegment(source: .others, text: travel, isFinal: true,
                                                                start: 2, end: 12, language: "de-DE")])
        _ = try archive.save(record)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archive.directoryURL,
                                                                       includingPropertiesForKeys: nil)
        let archiveBytes = try Dictionary(uniqueKeysWithValues: archiveFiles.map { ($0, try Data(contentsOf: $0)) })
        let directory = root.appendingPathComponent("Search Index")
        let old = HistoryIndex(directory: directory, embedder: LegacyEmptyAppleWords())
        _ = try await old.sync([record])
        let fileURL = directory.appendingPathComponent(record.id + ".vectors")
        XCTAssertTrue(try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: fileURL))).chunks.isEmpty)
        let embedder = NaturalLanguageEmbedder()
        XCTAssertNotEqual(embedder.signature, LegacyEmptyAppleWords().signature)
        let reopened = HistoryIndex(directory: directory, embedder: embedder)
        let stale = try await reopened.indexedIDs()
        XCTAssertTrue(stale.isEmpty, "A new recipe must invalidate even an unchanged empty-vector entry")
        let report = try await reopened.sync([record])
        XCTAssertEqual(report.embedded, 1)
        XCTAssertEqual(report.unchanged, 0)
        let vector = await embedder.embed(travel, transcribedIn: "de-DE")
        let expected = try XCTUnwrap(vector)
        let chunks = HistoryChunker.chunks(for: record)
        let stored = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: fileURL)))
        XCTAssertEqual(stored.chunks, [StoredChunkVector(ordinal: 0, vector: expected,
                       fingerprint: HistoryChunker.fingerprint(chunks, salt: embedder.signature))])
        XCTAssertEqual(try archive.all(), [record])
        for (url, bytes) in archiveBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
    }

    func testEnglishCaseNormalizationRemainsUnchanged() throws {
        let model = try XCTUnwrap(NLEmbedding.wordEmbedding(for: .english),
                                 "English Apple word model must already be installed")
        let values = try XCTUnwrap(model.vector(for: "airport"))
        let expected = HistoryVector(model: "w:en:\(model.revision)", values: values.map(Float.init))
        let embedder = NaturalLanguageEmbedder()
        XCTAssertEqual(embedder.embed("airport", language: .english), expected)
        XCTAssertEqual(embedder.embed("Airport", language: .english), expected)
    }

    func testSpanishUppercaseQueryKeepsLowercaseVocabularyFallback() throws {
        let model = try XCTUnwrap(NLEmbedding.wordEmbedding(for: .spanish))
        XCTAssertNil(model.vector(for: "PASAPORTE"), "This control must exercise the lowercase fallback")
        let values = try XCTUnwrap(model.vector(for: "pasaporte"))
        let expected = HistoryVector(model: "w:es:\(model.revision)", values: values.map(Float.init))
        let embedder = NaturalLanguageEmbedder()
        XCTAssertEqual(embedder.embed("PASAPORTE", language: .spanish), expected)
    }
}

private struct LegacyEmptyAppleWords: HistoryEmbedder {
    let signature = "nl-noun-mean+sentence-v2"
    func embed(_ text: String) -> HistoryVector? { nil }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}
