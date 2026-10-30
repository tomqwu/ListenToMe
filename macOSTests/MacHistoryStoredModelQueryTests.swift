import Foundation
import NaturalLanguage
import XCTest
@testable import ListenToMeCore

@MainActor
final class MacHistoryStoredModelQueryTests: XCTestCase {
    private let topic = "Flüge Hotel Konferenz Berlin Formulare"

    private func models() throws -> (NLEmbedding, NLEmbedding) {
        let word = try XCTUnwrap(NLEmbedding.wordEmbedding(for: .german), "German word model must already be installed")
        let sentence = try XCTUnwrap(NLEmbedding.sentenceEmbedding(for: .german),
                                     "German sentence model must already be installed")
        return (word, sentence)
    }

    func testStoredSentencePassageRemainsRelatedWhenWordModelIsAvailable() async throws {
        let (_, sentence) = try models()
        let raw = try XCTUnwrap(sentence.vector(for: topic))
        let expected = HistoryVector(model: "s:de:\(sentence.revision)", values: raw.map(Float.init))
        let apple = NaturalLanguageEmbedder()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredSentenceQuery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = SessionRecord(id: "sentence-record", title: "Synthetic topic", date: .distantPast,
                                   transcript: topic, summary: "")
        // Test setup stores a genuine framework sentence vector under the current signature,
        // representing an archive created before the word asset became available. No fake vector.
        let saved = HistoryIndex(directory: directory,
                                 embedder: CapturedAppleSentence(vector: expected, signature: apple.signature))
        _ = try await saved.sync([record])
        let url = directory.appendingPathComponent(record.id + ".vectors")
        let before = try Data(contentsOf: url)
        XCTAssertEqual(try XCTUnwrap(HistoryIndexFile.decode(before)).chunks.map(\.model), [expected.model])
        let reopened = HistoryIndex(directory: directory, embedder: apple)
        let ids = try await reopened.indexedIDs()
        XCTAssertEqual(ids, [record.id])
        let queries = apple.embedQuery(topic, models: [expected.model])
        XCTAssertEqual(queries, [expected], "A present word model must not replace the requested sentence representation")
        let results = await reopened.search(topic, in: [record])
        XCTAssertTrue(results.contains { $0.id == record.id && $0.isRelated }, "Keyword survival alone cannot satisfy semantic continuity")
        XCTAssertEqual(try Data(contentsOf: url), before, "Search must not re-embed or overwrite the saved sentence vector")
    }

    func testBothStoredGermanRepresentationsReceiveExactCurrentQueries() throws {
        let (_, sentence) = try models()
        let apple = NaturalLanguageEmbedder()
        let word = try XCTUnwrap(apple.embed(topic, language: .german))
        XCTAssertTrue(word.model.hasPrefix("w:de:"))
        let raw = try XCTUnwrap(sentence.vector(for: topic))
        let expectedSentence = HistoryVector(model: "s:de:\(sentence.revision)", values: raw.map(Float.init))
        let queries = apple.embedQuery(topic, models: [word.model, expectedSentence.model])
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(queries.map(\.model), queries.map(\.model).sorted(), "Stable order for mixed representations")
        XCTAssertEqual(apple.embedQuery(topic, models: [expectedSentence.model, word.model]), queries)
        XCTAssertEqual(Set(queries.map(\.model)), [word.model, expectedSentence.model])
        XCTAssertEqual(queries.first { $0.model == word.model }, word)
        XCTAssertEqual(queries.first { $0.model == expectedSentence.model }, expectedSentence)
        XCTAssertEqual(apple.embedQuery(topic, models: [word.model]), [word])
    }

    func testSentenceMinimumAndStaleRevisionRefusalRemainUnchanged() throws {
        let (word, sentence) = try models()
        let apple = NaturalLanguageEmbedder()
        let wordTag = "w:de:\(word.revision)"
        let sentenceTag = "s:de:\(sentence.revision)"
        XCTAssertTrue(apple.embedQuery("Flughafen", models: [sentenceTag]).isEmpty,
                      "One-word queries cannot bypass the existing sentence-model minimum")
        XCTAssertEqual(apple.embedQuery("Flughafen", models: [wordTag]).count, 1)
        XCTAssertTrue(apple.embedQuery(topic, models: ["w:de:-1", "s:de:-1"]).isEmpty)
        XCTAssertTrue(apple.embedQuery(topic, models: ["x:de:1", "s:de:not-a-revision", "s:de:1:extra"]).isEmpty)
        let malformed = ["s::de:\(sentence.revision)", "s:de:\(sentence.revision):", "w::de:\(word.revision)", "s::1"]
        for tag in malformed {
            XCTAssertTrue(apple.embedQuery(topic, models: [tag]).isEmpty, "Malformed tag: \(tag)")
        }
        let supported = NLEmbedding.supportedRevisions(for: .german)
            .union(NLEmbedding.supportedSentenceEmbeddingRevisions(for: .german))
        let unavailable = try XCTUnwrap(supported.last) + 1
        XCTAssertGreaterThan(unavailable, 0)
        XCTAssertFalse(supported.contains(unavailable))
        let unavailableWord = NLEmbedding.wordEmbedding(for: .german, revision: unavailable)
        let unavailableSentence = NLEmbedding.sentenceEmbedding(for: .german, revision: unavailable)
        // The framework can return a different revision instead of nil for an unsupported request.
        XCTAssertNotEqual(unavailableWord?.revision, unavailable)
        XCTAssertNotEqual(unavailableSentence?.revision, unavailable)
        print("Unavailable revision \(unavailable): word=\(String(describing: unavailableWord?.revision)), " +
              "sentence=\(String(describing: unavailableSentence?.revision))")
        XCTAssertTrue(apple.embedQuery(topic, models: ["w:de:\(unavailable)", "s:de:\(unavailable)"]).isEmpty,
                      "Unavailable positive revisions must not reuse or relabel a current model")
        XCTAssertTrue(apple.embedQuery(topic, models: []).isEmpty)
    }
}

private struct CapturedAppleSentence: HistoryEmbedder {
    let vector: HistoryVector
    let signature: String
    func embed(_ text: String) -> HistoryVector? { vector }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}
