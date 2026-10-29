import Foundation
import XCTest
@testable import ListenToMeCore
@testable import ListenToMeIOS

/// Synthetic runtime-contract checks; not multilingual retrieval-quality acceptance.
@MainActor
final class MultilingualHistoryEmbedderTests: XCTestCase {
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

    func testOptionalPassagesCannotEraseFallbackSearchOrAskResults() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryGroups-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fallback = GroupFallback()
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: try assets(), fallback: fallback)
        let index = HistoryIndex(directory: folder, embedder: adapter)
        func record(_ id: String, _ text: String, _ language: String) -> SessionRecord {
            SessionRecord(id: id, title: id, date: .distantPast, transcript: text, summary: "",
                          segments: [TranscriptSegment(source: .others, text: text, isFinal: true,
                                                       start: 0, end: 1, language: language)])
        }
        let original = [record("apple-target", "Apple target about archival roof repairs", "en")]
            + (0..<4).map { record("apple-noise-\($0)", "Apple unrelated note \($0)", "en") }
        let query = "Das undichte Dach muss vor dem nächsten Regen repariert werden."
        try await index.sync(original)
        let before = await index.search(query, in: original).filter(\.isRelated).map(\.id)
        XCTAssertEqual(before, ["apple-target"])
        let optional = (0..<40).map { record("mpnet-\($0)", query, "de") }
        let combined = original + optional
        try await index.sync(combined)
        let fallbackData = try Data(contentsOf: folder.appendingPathComponent("apple-target.vectors"))
        let storedFallback = try XCTUnwrap(HistoryIndexFile.decode(fallbackData))
        XCTAssertEqual(Set(storedFallback.chunks.map(\.model)), [GroupFallback.model])
        var storedModels = Set(storedFallback.chunks.map(\.model))
        for record in optional {
            let data = try Data(contentsOf: folder.appendingPathComponent(record.id + ".vectors"))
            let stored = try XCTUnwrap(HistoryIndexFile.decode(data), record.id)
            let chunks = HistoryChunker.chunks(for: record)
            XCTAssertEqual(chunks.count, 1, record.id)
            let sourceChunk = try XCTUnwrap(chunks.first, record.id)
            XCTAssertEqual(stored.fingerprint, HistoryChunker.fingerprint(chunks, salt: adapter.signature), record.id)
            XCTAssertEqual(stored.chunks.count, 1, record.id)
            let vector = try XCTUnwrap(stored.chunks.first, record.id)
            XCTAssertEqual(vector.ordinal, 0, record.id)
            XCTAssertEqual(vector.fingerprint,
                           HistoryChunker.fingerprint([sourceChunk], salt: adapter.signature), record.id)
            XCTAssertEqual(vector.model, MultilingualHistoryEmbedder.modelIdentifier, record.id)
            XCTAssertEqual(vector.values.count, 768, record.id)
            XCTAssertTrue(vector.values.contains { $0 != 0 }, record.id)
            XCTAssertTrue(vector.scale.isFinite && vector.scale > 0, record.id)
            storedModels.insert(vector.model)
        }
        XCTAssertEqual(storedModels, [GroupFallback.model, MultilingualHistoryEmbedder.modelIdentifier])
        let queryVectors = await adapter.embedQuery(query, models: storedModels)
        XCTAssertEqual(Set(queryVectors.map(\.model)), storedModels)
        XCTAssertEqual(queryVectors.count, 2, "One query vector for each actually persisted model")
        let after = await index.search(query, in: combined).filter { $0.id.hasPrefix("apple-") && $0.isRelated }
        let passages = await index.retrieve(query, in: combined, limit: 100).filter { $0.recordID.hasPrefix("apple-") }
        XCTAssertEqual(after.map(\.id), before, "Actual optional runtime must not alter fallback admission statistics")
        XCTAssertEqual(passages.map(\.recordID), ["apple-target"])
        XCTAssertEqual(passages.first?.text, original[0].transcript)
        XCTAssertEqual(adapter.relevanceGroup(for: GroupFallback.model), fallback.relevanceGroup(for: GroupFallback.model))
        XCTAssertNotEqual(adapter.relevanceGroup(for: MultilingualHistoryEmbedder.modelIdentifier),
                          adapter.relevanceGroup(for: GroupFallback.model))
    }

    func testOptionalRoutingUsesActualAppleAvailability() async throws {
        let apple = NaturalLanguageEmbedder()
        let supported = apple.supports(.spanish)
        print("History Spanish Apple support on this native host: \(supported)")
        let text = "Reservemos vuelos y hoteles para la conferencia de Berlín. Dana se encarga de los visados y del reembolso del viaje."
        let baseline = await apple.embed(text, transcribedIn: "es-ES")
        if supported { _ = try XCTUnwrap(baseline) } else { XCTAssertNil(baseline) }
        let installedDirectory = try assets()
        for directory in [installedDirectory, URL(fileURLWithPath: "/missing-local-runtime")] {
            let adapter = MultilingualHistoryEmbedder(installedModelDirectory: directory, fallback: apple)
            let explicit = await adapter.embed(text, transcribedIn: "es-ES")
            let detected = await adapter.embed(text)
            if supported {
                XCTAssertEqual(explicit, baseline)
                XCTAssertEqual(detected, baseline)
                let filler = "Vale, sí. Bueno, eh, veamos. Claro, claro. Me parece bien."
                let appleFiller = await apple.embed(filler, transcribedIn: "es")
                let rejected = await adapter.embed(filler, transcribedIn: "es")
                XCTAssertNil(appleFiller)
                XCTAssertNil(rejected, "Apple eligibility refusal must not fall through to MPNet")
            } else if directory == installedDirectory {
                let vector = try XCTUnwrap(explicit)
                XCTAssertEqual(vector.model, MultilingualHistoryEmbedder.modelIdentifier)
                XCTAssertEqual(vector.values.count, 768)
                XCTAssertTrue(vector.values.allSatisfy(\.isFinite))
                XCTAssertEqual(vector.values.reduce(Float(0)) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
                XCTAssertEqual(detected, vector)
            } else {
                XCTAssertNil(explicit)
                XCTAssertNil(detected)
            }
            if let vector = explicit {
                let queries = await adapter.embedQuery("aeropuerto", models: [vector.model])
                XCTAssertEqual(queries.count, 1)
                XCTAssertEqual(try XCTUnwrap(queries.first).model, vector.model)
            }
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await adapter.embed(text, transcribedIn: "es")
            }
            let late = await cancelled.value
            XCTAssertNil(late)
        }
    }

    func testRoutingUpgradeRebuildsOldOptionalVectorsWithoutChangingConversation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AppleRouting-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "Reservemos vuelos y hoteles para la conferencia de Berlín. Dana se encarga de los visados y del reembolso del viaje."
        let record = SessionRecord(id: "spanish", title: "Original", date: .distantPast, transcript: text, summary: "",
                                   segments: [TranscriptSegment(source: .others, text: text, isFinal: true,
                                                                start: 0, end: 1, language: "es-ES")])
        let old = HistoryIndex(directory: folder, embedder: OverrideAppleRuntime())
        _ = try await old.sync([record])
        let saved = folder.appendingPathComponent(record.id + ".vectors")
        let before = try Data(contentsOf: saved)
        let oldFile = try XCTUnwrap(HistoryIndexFile.decode(before))
        XCTAssertEqual(oldFile.chunks.map(\.model), [MultilingualHistoryEmbedder.modelIdentifier])
        let apple = NaturalLanguageEmbedder()
        let adapter = MultilingualHistoryEmbedder(installedModelDirectory: try assets(), fallback: apple)
        let selected = await adapter.embed(text, transcribedIn: "es-ES")
        let expected = try XCTUnwrap(selected)
        if apple.supports(.spanish) {
            let baseline = await apple.embed(text, transcribedIn: "es-ES")
            XCTAssertEqual(expected, try XCTUnwrap(baseline))
        } else {
            XCTAssertEqual(expected.model, MultilingualHistoryEmbedder.modelIdentifier)
            XCTAssertEqual(expected.values.count, 768)
        }
        XCTAssertNotEqual(adapter.signature, OverrideAppleRuntime().signature)
        let reopened = HistoryIndex(directory: folder, embedder: adapter)
        let stale = try await reopened.indexedIDs()
        XCTAssertTrue(stale.isEmpty, "Old optional vectors must be discarded before any search can reuse them")
        let rebuilt = try await reopened.sync([record])
        XCTAssertEqual(rebuilt.embedded, 1)
        XCTAssertEqual(rebuilt.unchanged, 0)
        let data = try Data(contentsOf: saved)
        let file = try XCTUnwrap(HistoryIndexFile.decode(data))
        let chunks = HistoryChunker.chunks(for: record)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(file.chunks, [StoredChunkVector(ordinal: 0, vector: expected,
                       fingerprint: HistoryChunker.fingerprint(chunks, salt: adapter.signature))])
        XCTAssertEqual(file.fingerprint, HistoryChunker.fingerprint(HistoryChunker.chunks(for: record), salt: adapter.signature))
        XCTAssertNotEqual(data, before)
        XCTAssertEqual(record.transcript, text)
        XCTAssertEqual(record.segments?.first?.language, "es-ES")
    }

    private func assets() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["LISTENTOME_MPNET_TEST_ASSETS"], !path.isEmpty else {
            throw XCTSkip("Optional actual MPNet runtime requires explicit local LISTENTOME_MPNET_TEST_ASSETS; never downloads")
        }
        // Reinstalling a simulator app relocates its data container. Relative fixtures travel with it.
        let directory = path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true)
            : URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(path)
        for name in ["config.json", "model.safetensors", "sentencepiece.bpe.model", "tokenizer.json",
                     "tokenizer_config.json", "special_tokens_map.json"] {
            let file = directory.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            XCTAssertEqual(values.isRegularFile, true, "Missing local runtime fixture: \(name)")
            XCTAssertGreaterThan(values.fileSize ?? 0, 0, "Empty local runtime fixture: \(name)")
        }
        return directory
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

/// Controlled fallback scores isolate composition; optional vectors still use the actual local model.
private struct GroupFallback: HistoryEmbedder {
    static let model = "group-test-fallback"
    let signature = "group-test-fallback-v1"
    func relevanceGroup(for model: String) -> String { "independent-fallback-group" }
    func embed(_ text: String) -> HistoryVector? {
        HistoryVector(model: Self.model, values: text.hasPrefix("Apple target") ? [1, 0] : [0, 1])
    }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] {
        models.contains(Self.model) ? [HistoryVector(model: Self.model, values: [1, 0])] : []
    }
}

/// Previously installed policy replaced Spanish even when Apple already supported it.
private struct OverrideAppleRuntime: HistoryEmbedder {
    let signature = "mpnet-4328cf26390c98c5e3c738b4460a05b95f4911f5-mean128-content-v2+nl-noun-mean+sentence-v2"
    func embed(_ text: String) -> HistoryVector? {
        HistoryVector(model: MultilingualHistoryEmbedder.modelIdentifier, values: [1, 0])
    }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}
