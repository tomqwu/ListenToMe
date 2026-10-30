import Foundation
import XCTest
@testable import ListenToMeCore

@MainActor
final class HistoryDefaultBackendTests: XCTestCase {
    func testSharedAppleBaselineDiscardsOnlyStaleOptionalVectorsAndKeepsLiteralHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryBaseline-" + UUID().uuidString)
        let suite = "HistoryBaseline-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        // The suite is a preservation sentinel, not injected production configuration.
        // Default composition itself must never acquire a dependency on this legacy preference.
        defaults.set(true, forKey: "multilingualHistorySearchEnabled")
        let assets = root.appendingPathComponent("History Models/legacy-download-sentinel.bin")
        try FileManager.default.createDirectory(at: assets.deletingLastPathComponent(), withIntermediateDirectories: true)
        let assetBytes = Data("existing downloaded asset must not be deleted or read as a model".utf8)
        try assetBytes.write(to: assets)
        let text = "Copperlanternfixture launch budget supplier handbook."
        let segment = TranscriptSegment(source: .others, text: text, isFinal: true, start: 7, end: 9)
        let record = SessionRecord(id: "baseline", title: "Preserved original title", date: .distantPast,
                                   transcript: text, summary: "", segments: [segment], notes: "Keep original notes.",
                                   language: "en-US", languages: ["en-US"])
        let archive = SessionArchive(directory: root.appendingPathComponent("Conversations"))
        try archive.save(record)
        let archiveFile = archive.directoryURL.appendingPathComponent("baseline.json")
        let archiveBytes = try Data(contentsOf: archiveFile)
        let indexDirectory = HistoryIndex.directory(besideArchive: archive.directoryURL)
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        let oldModel = "mpnet-4328cf26390c98c5e3c738b4460a05b95f4911f5-mean128-content-v2"
        let oldSignature = oldModel + "+nl-noun-case+sentence-v3+apple-first-v1:de,es"
        try JSONSerialization.data(withJSONObject: ["version": HistoryIndex.version, "embedder": oldSignature])
            .write(to: indexDirectory.appendingPathComponent("index.json"))
        // Deliberately synthetic two-dimensional cache sentinel; never inference evidence.
        let sentinel = HistoryVector(model: oldModel, values: [1, 0])
        let stale = StoredRecordVectors(fingerprint: 0, chunks: [StoredChunkVector(ordinal: 0, vector: sentinel)])
        let staleFile = indexDirectory.appendingPathComponent("baseline.vectors")
        try HistoryIndexFile.encode(stale).write(to: staleFile)

        let model = HistorySearchModel.shared(besideArchive: archive.directoryURL)
        model.records = { [record] }
        let initialIDs = try await model.index.indexedIDs()
        XCTAssertTrue(initialIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path), "Discard only stale derived vectors")
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: indexDirectory.appendingPathComponent("index.json"))) as? [String: Any])
        XCTAssertEqual(manifest["embedder"] as? String, NaturalLanguageEmbedder().signature)
        _ = try await model.index.sync([record])
        let rebuilt = try XCTUnwrap(HistoryIndexFile.decode(Data(contentsOf: staleFile)))
        XCTAssertTrue(rebuilt.chunks.allSatisfy { $0.model.hasPrefix("w:") || $0.model.hasPrefix("s:") },
                      "Only actual installed Apple vectors, or truthful no-vector fallback, are accepted")
        model.search("copperlanternfixture")
        await model.waitForSearch()
        let results = try XCTUnwrap(model.results(for: "copperlanternfixture"))
        XCTAssertEqual(results.map(\.id), [record.id])
        XCTAssertTrue(results.allSatisfy(\.matchesWords))
        XCTAssertEqual(try Data(contentsOf: archiveFile), archiveBytes)
        XCTAssertEqual(try archive.all(), [record])
        XCTAssertEqual(try Data(contentsOf: assets), assetBytes)
        XCTAssertTrue(defaults.bool(forKey: "multilingualHistorySearchEnabled"))
    }
}
