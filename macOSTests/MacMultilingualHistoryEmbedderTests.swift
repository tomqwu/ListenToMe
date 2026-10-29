import Foundation
import XCTest
import ListenToMeCore


/// Synthetic runtime-contract checks; not multilingual retrieval-quality acceptance.
@MainActor
final class MacMultilingualHistoryEmbedderTests: XCTestCase {
    func testInstalledRuntimeProducesPinnedLocalVectors() async throws {
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: try assets(), fallback: RuntimeFallback())
        let examples = [("de", "Das undichte Dach muss vor dem nächsten Regen repariert werden."),
                        ("es", "El tejado necesita una reparación antes de la próxima lluvia."),
                        ("ja", "次の雨が降る前に屋根の雨漏りを修理する必要があります。"),
                        ("ko", "다음 비가 오기 전에 지붕의 누수를 수리해야 합니다.")]
        for (language, text) in examples {
            let result = await adapter.embed(text, transcribedIn: language)
            let vector = try XCTUnwrap(result, language)
            XCTAssertEqual(vector.model, MultilingualHistoryEmbedder.modelIdentifier)
            XCTAssertEqual(vector.values.count, 768)
            XCTAssertTrue(vector.values.allSatisfy(\.isFinite))
            XCTAssertEqual(vector.values.reduce(Float(0)) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
            let queries = await adapter.embedQuery(text, models: [vector.model])
            XCTAssertEqual(queries.count, 1)
            XCTAssertEqual(queries.first?.model, vector.model)
            if let query = queries.first, query.values.count == vector.values.count {
                let similarity = zip(query.values, vector.values).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                XCTAssertGreaterThan(similarity, 0.9999)
            }
        }
    }

    func testAbsentRuntimeAndOtherLanguagesKeepAppleRouting() async {
        let fallback = RuntimeFallback()
        let absent = MultilingualHistoryEmbedder(fallback: fallback)
        XCTAssertEqual(absent.signature, fallback.signature)
        let original = "Keep the complete original meeting text."
        let english = await absent.embed(original, transcribedIn: "en-US")
        XCTAssertEqual(english, RuntimeFallback.vector)
        let german = await absent.embed("Original deutscher Text", transcribedIn: "de-DE")
        XCTAssertEqual(german, RuntimeFallback.vector)
        let installed = MultilingualHistoryEmbedder(installedModelDirectory: URL(fileURLWithPath: "/missing-local-runtime"),
                                                    fallback: fallback)
        let chinese = await installed.embed("保留原始内容。", transcribedIn: "zh-CN")
        XCTAssertEqual(chinese, RuntimeFallback.vector)
        let calls = await fallback.calls
        XCTAssertEqual(calls, [original + "|en-US", "Original deutscher Text|de-DE", "保留原始内容。|zh-CN"])
    }

    func testLongTailIsNotSilentlyTruncated() async throws {
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: try assets(), fallback: RuntimeFallback())
        let prefix = String(repeating: "Das Dach muss repariert werden. ", count: 160)
        let source = prefix + "Die Patientin braucht dringend ein neues Medikament."
        let vector = await adapter.embed(source, transcribedIn: "de")
        XCTAssertNil(vector, "A prefix-only roof vector would silently omit the medical topic at the tail")
        let query = await adapter.embedQuery(source, models: [MultilingualHistoryEmbedder.modelIdentifier])
        XCTAssertTrue(query.isEmpty, "The same complete-text limit applies to queries")
        XCTAssertTrue(source.hasSuffix("Die Patientin braucht dringend ein neues Medikament."))
    }

    func testCancellationMissingAssetsAndModelIsolation() async {
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: URL(fileURLWithPath: "/missing-local-runtime"),
                                                 fallback: RuntimeFallback())
        let missing = await adapter.embed("Das Dach muss repariert werden.", transcribedIn: "de")
        XCTAssertNil(missing, "Explicit missing local assets must not yield an unrelated fallback vector")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await adapter.embed("Das Dach muss repariert werden.", transcribedIn: "de")
        }
        let late = await cancelled.value
        XCTAssertNil(late)
        let query = await adapter.embedQuery("Das Dach muss repariert werden.", models: ["unrelated-model"])
        XCTAssertTrue(query.isEmpty)
    }

    func testStoredModelsReceiveShortAndAmbiguousQueriesWithoutLanguageGuessFiltering() async throws {
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: try assets(), fallback: RuntimeFallback())
        let expected: Set<String> = [MultilingualHistoryEmbedder.modelIdentifier, RuntimeFallback.vector.model]
        // A short query's guessed language must not hide an installed multilingual index.
        for query in ["Flughafen", "comida", "食事", "공항", "agreement", "xqz"] {
            let vectors = await adapter.embedQuery(query, models: expected.union(["incompatible-model"]))
            XCTAssertEqual(Set(vectors.map(\.model)), expected, query)
            XCTAssertEqual(vectors.count, expected.count, "Exactly one query vector per compatible stored model")
            let multilingual = try XCTUnwrap(vectors.first { $0.model == MultilingualHistoryEmbedder.modelIdentifier }, query)
            XCTAssertEqual(multilingual.values.count, 768)
            XCTAssertTrue(multilingual.values.allSatisfy(\.isFinite))
        }
        let absent = await adapter.embedQuery("agreement", models: ["incompatible-model"])
        XCTAssertTrue(absent.isEmpty, "Do not return vectors for models absent from the index")
    }

    func testEligibilityUpgradeInvalidatesPersistedLegacyVectorsBeforeReuse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MPNetUpgrade-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "Vale, sí. Bueno, eh, veamos. Claro, claro. Me parece bien."
        let record = SessionRecord(id: "filler", title: "Original conversation", date: .distantPast,
                                   transcript: text, summary: "")
        let legacy = HistoryIndex(directory: directory, embedder: LegacyRuntime())
        let seeded = try await legacy.sync([record])
        XCTAssertEqual(seeded.embedded, 1)
        let oldIDs = try await legacy.indexedIDs()
        XCTAssertEqual(oldIDs, [record.id])
        let saved = directory.appendingPathComponent("filler.vectors")
        let before = try Data(contentsOf: saved)
        let current = MultilingualHistoryEmbedder(installedModelDirectory: URL(fileURLWithPath: "/missing-local-runtime"),
                                                 fallback: RuntimeFallback())
        let reopened = HistoryIndex(directory: directory, embedder: current)
        let currentIDs = try await reopened.indexedIDs()
        XCTAssertTrue(currentIDs.isEmpty, "Opening the new content policy must discard legacy derived vectors before reuse")
        let rebuilt = try await reopened.sync([record])
        XCTAssertEqual(rebuilt.embedded, 1, "An unchanged transcript must still be reconsidered under the new policy")
        XCTAssertEqual(rebuilt.unchanged, 0)
        XCTAssertNotEqual(try Data(contentsOf: saved), before, "Legacy filler vectors cannot survive the policy upgrade")
        XCTAssertEqual(record.transcript, text, "Only derived index data changes")
    }

    private func assets() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["LISTENTOME_MPNET_TEST_ASSETS"], !path.isEmpty else {
            throw XCTSkip("Optional actual MPNet runtime requires explicit local LISTENTOME_MPNET_TEST_ASSETS; never downloads")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private actor RuntimeFallback: HistoryEmbedder {
    nonisolated let signature = "runtime-test-apple"
    nonisolated static let vector = HistoryVector(model: "runtime-test-apple", values: [1, 0])
    private(set) var calls: [String] = []
    func embed(_ text: String) async -> HistoryVector? { calls.append(text); return Self.vector }
    func embed(_ text: String, transcribedIn language: String) async -> HistoryVector? {
        calls.append(text + "|" + language); return Self.vector
    }
    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        models.contains(signature) ? [Self.vector] : []
    }
}

/// Historical persisted identity: deliberately fixed, independent of the current runtime constant.
private struct LegacyRuntime: HistoryEmbedder {
    let signature = "mpnet-4328cf26390c98c5e3c738b4460a05b95f4911f5-mean128-v1+runtime-test-apple"
    func embed(_ text: String) -> HistoryVector? {
        HistoryVector(model: "mpnet-4328cf26390c98c5e3c738b4460a05b95f4911f5-mean128-v1", values: [1, 0])
    }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}
