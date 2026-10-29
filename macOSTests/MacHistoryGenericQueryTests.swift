import Foundation
import CryptoKit
import NaturalLanguage
import XCTest
@testable import ListenToMeCore

@MainActor
final class MacHistoryGenericQueryTests: XCTestCase {
    private let queries = [
        "de": ["der Plan für nächste Woche", "unsere Pläne für die letzte Woche",
               "die Zeit für die Besprechung", "die Fragen zum Projekt"],
        "es": ["el plan para la próxima semana", "nuestros planes para la última semana",
               "el tiempo para la reunión", "las preguntas sobre el proyecto"]
    ]

    private func prerequisites(_ code: String) throws -> NLLanguage {
        let language = NLLanguage(rawValue: code)
        XCTAssertTrue(NLTagger.availableTagSchemes(for: .word, language: language).contains(.lexicalClass),
                      "Required installed lexical assets: \(code)")
        XCTAssertTrue(NaturalLanguageEmbedder().supports(language), "Required installed Apple embedding: \(code)")
        return language
    }

    private func records(_ code: String) throws -> [SessionRecord] {
        let fixture = try XCTUnwrap(MultilingualHistoryQualityTests.fixtures[code])
        let ids = ["budget", "hiring", "outage", "travel", "design", "lunch", "legal", "family"]
        return zip(ids, fixture[0]).map { id, text in
            SessionRecord(id: id, title: id, date: .distantPast, transcript: text, summary: "")
        }
    }

    private func checkGeneric(_ code: String) async throws {
        _ = try prerequisites(code)
        let apple = NaturalLanguageEmbedder()
        let archive = try records(code)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GenericQuery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = HistoryIndex(directory: directory, embedder: apple)
        _ = try await index.sync(archive)
        for query in try XCTUnwrap(queries[code]) {
            XCTAssertEqual(HistoryContentEligibility.evaluate(query, language: code, kind: .query), .insufficientContent, query)
            let related = await index.search(query, in: archive).filter(\.isRelated)
            XCTAssertTrue(related.isEmpty, "\(code) \(query): related \(related.map(\.id))")
        }
        // These exact temporal concepts are already excluded by English Ask's literal-term policy.
        for query in try XCTUnwrap(queries[code]).prefix(2) {
            let excerpts = await index.retrieve(query, in: archive)
            XCTAssertTrue(excerpts.isEmpty, "\(query): Ask admitted \(excerpts.map(\.recordID))")
            XCTAssertNil(HistoryQuestion.request(question: query, passages: excerpts))
        }
        let literal = try XCTUnwrap(queries[code]?.first)
        let exact = SessionRecord(id: "literal", title: "Literal search", date: .distantPast,
                                  transcript: literal, summary: "")
        _ = try await index.sync(archive + [exact])
        let results = await index.search(literal, in: archive + [exact])
        XCTAssertTrue(results.contains { $0.id == exact.id && $0.matchesWords && !$0.isRelated },
                      "Ordinary keyword search remains available without inventing semantic relevance")
    }

    func testGermanGenericQueriesDoNotInventRelatedTopicsOrAskExcerpts() async throws {
        try await checkGeneric("de")
    }

    func testSpanishGenericQueriesDoNotInventRelatedTopicsOrAskExcerpts() async throws {
        try await checkGeneric("es")
    }

    func testRealTopicsAddedToTheSameScaffoldingRemainSearchable() async throws {
        for code in ["de", "es"] {
            let language = try prerequisites(code)
            let archive = try records(code)
            let travel = try XCTUnwrap(archive.first { $0.id == "travel" })
            let query = try XCTUnwrap(queries[code]?.first) + ": " + travel.transcript
            let apple = NaturalLanguageEmbedder()
            let result = await apple.embed(travel.transcript, transcribedIn: code)
            let vector = try XCTUnwrap(result)
            XCTAssertEqual(HistoryContentEligibility.evaluate(query, language: code, kind: .query), .eligible)
            XCTAssertFalse(apple.embedQuery(query, models: [vector.model]).isEmpty)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GenericTopic-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let index = HistoryIndex(directory: directory, embedder: apple)
            _ = try await index.sync(archive)
            for record in archive {
                let bytes = try Data(contentsOf: directory.appendingPathComponent(record.id + ".vectors"))
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                print("QueryOnly passage \(code) \(record.id) \(digest)")
            }
            let before = try Data(contentsOf: directory.appendingPathComponent("travel.vectors"))
            let related = await index.search(query, in: archive)
            XCTAssertTrue(related.contains { $0.id == "travel" && $0.isRelated }, code)
            let excerpts = await index.retrieve(query, in: archive)
            XCTAssertTrue(excerpts.contains { $0.recordID == "travel" }, code)
            let request = try XCTUnwrap(HistoryQuestion.request(question: query, passages: excerpts))
            XCTAssertTrue(request.sent.contains { $0.recordID == "travel" })
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("travel.vectors")), before)
            let sentence = try XCTUnwrap(NLEmbedding.sentenceEmbedding(for: language))
            XCTAssertEqual(apple.embedQuery(query, models: ["s:\(code):\(sentence.revision)"]).count, 1)
        }
    }

    func testStoredSentenceModelsCannotBypassGenericQueryRefusal() throws {
        for code in ["de", "es"] {
            let language = try prerequisites(code)
            let sentence = try XCTUnwrap(NLEmbedding.sentenceEmbedding(for: language))
            let tag = "s:\(code):\(sentence.revision)"
            for query in try XCTUnwrap(queries[code]) {
                XCTAssertTrue(NaturalLanguageEmbedder().embedQuery(query, models: [tag]).isEmpty, "\(tag) \(query)")
            }
        }
    }

    func testOptionalRuntimeRefusesKnownGenericQueriesAndKeepsTopicVectors() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LISTENTOME_MPNET_TEST_ASSETS"])
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: URL(fileURLWithPath: path),
                                                fallback: GenericQueryNoApple())
        for code in ["de", "es"] {
            _ = try prerequisites(code)
            for query in try XCTUnwrap(queries[code]) {
                let vectors = await adapter.embedQuery(query, models: [MultilingualHistoryEmbedder.modelIdentifier])
                XCTAssertTrue(vectors.isEmpty, "\(code) \(query)")
            }
            let topic = try XCTUnwrap(records(code).first { $0.id == "travel" }).transcript
            let query = try XCTUnwrap(queries[code]?.first) + ": " + topic
            let vectors = await adapter.embedQuery(query, models: [MultilingualHistoryEmbedder.modelIdentifier])
            XCTAssertEqual(vectors.map(\.model), [MultilingualHistoryEmbedder.modelIdentifier])
            XCTAssertTrue(vectors.allSatisfy { $0.values.count == 768 && $0.values.allSatisfy(\.isFinite) })
        }
    }

    func testCompoundsAmbiguityAndUnavailableLexicalAssetsKeepTheirExistingBehavior() throws {
        _ = try prerequisites("de")
        for word in ["Plan", "plan", "comida"] {
            XCTAssertEqual(HistoryContentEligibility.evaluate(word, kind: .query), .unknown)
        }
        let apple = NaturalLanguageEmbedder()
        let original = try XCTUnwrap(apple.embed("Plan", language: .german))
        XCTAssertEqual(apple.embedQuery("Plan", models: [original.model]), [original],
                       "A stored-model language is not an explicit query-language hint")
        for word in ["Projektplan", "Reiseplanung", "Flugplan"] {
            XCTAssertEqual(HistoryContentEligibility.evaluate(word, language: "de", kind: .query), .eligible, word)
            XCTAssertTrue(HistoryQuestion.contentTerms(word).contains(word.lowercased()), word)
        }
        var unavailable = 0
        for (code, text) in [("ja", "はい、そうですね。ええと、考えてみましょう。"),
                             ("ko", "네, 그래요. 음, 어디 보자. 맞아요.")] {
            guard !NLTagger.availableTagSchemes(for: .word, language: NLLanguage(rawValue: code)).contains(.lexicalClass) else {
                continue
            }
            unavailable += 1
            XCTAssertEqual(HistoryContentEligibility.evaluate(text, language: code, kind: .query), .unknown)
        }
        XCTAssertGreaterThan(unavailable, 0, "Missing-capability branch must actually execute")
    }
}

private struct GenericQueryNoApple: HistoryEmbedder {
    let signature = "generic-query-without-apple"
    func embed(_ text: String) -> HistoryVector? { nil }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}
