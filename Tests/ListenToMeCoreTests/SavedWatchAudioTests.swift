import XCTest
@testable import ListenToMeCore

final class SavedWatchAudioTests: XCTestCase {
    private var root: URL!
    private var library: SavedAudioLibrary!
    private var source: URL!
    private let recording = UUID()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        source = root.appendingPathComponent("source.m4a")
        try Data([1, 2, 3, 4]).write(to: source)
        library = SavedAudioLibrary(root: root.appendingPathComponent("SavedAudio"), excludeFromBackup: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private func save(index: Int = 0, offset: Double = 0, date: Date = Date()) throws -> SavedAudioRun {
        try library.importWatchChunk(from: source, conversationID: "conversation", recordingID: recording,
            chunkIndex: index, startedAt: date, timelineOffset: offset, duration: 30)
    }

    func testRetryAndRelaunchKeepOneCopyAndItsOriginalTimeline() throws {
        let first = try save(offset: 60)
        library = SavedAudioLibrary(root: library.root, excludeFromBackup: true)
        XCTAssertEqual(try save(offset: 70), first)
        XCTAssertEqual(library.runs(for: "conversation"), [first])
        XCTAssertEqual(first.title(partCount: 1), "Apple Watch")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.url(for: first, conversationID: "conversation"))),
                       Data([1, 2, 3, 4]))
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(library.root))
        let line = TranscriptSegment(source: .you, text: "Watch", isFinal: true, start: 65, end: 70)
        XCTAssertEqual(SavedAudioSeek.target(for: line, index: 0, in: [first])?.time, 5)
        try library.delete(conversationID: "conversation")
        XCTAssertTrue(library.runs(for: "conversation").isEmpty)
    }

    func testInterruptedImportRecoversWithoutTrustingOrphanBytes() throws {
        let first = try save()
        let folder = try library.directory(for: "conversation")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("audio.json"))
        try Data([9]).write(to: XCTUnwrap(library.url(for: first, conversationID: "conversation")))
        _ = try save()
        XCTAssertEqual(library.runs(for: "conversation").count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(library.url(for: first, conversationID: "conversation"))),
                       Data([1, 2, 3, 4]))
    }

    func testCorruptManifestAndCopyFailureKeepSourceAndExistingManifest() throws {
        let folder = try library.directory(for: "conversation")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = folder.appendingPathComponent("audio.json")
        try Data("broken".utf8).write(to: manifest)
        XCTAssertThrowsError(try save())
        XCTAssertEqual(try String(contentsOf: manifest, encoding: .utf8), "broken")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.removeItem(at: source)
        XCTAssertThrowsError(try save())
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertTrue(library.runs(for: "conversation").isEmpty)
    }

    func testRetentionAndLegacyManifestCompatibility() throws {
        let old = try save(date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(library.deleteExpired(retentionDays: 7), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(
            library.url(for: old, conversationID: "conversation")).path))
        let run = SavedAudioRun(index: 1, source: .you, fileName: "old.m4a", startedAt: Date(),
                                timelineOffset: 0, timesMatchAudio: true)
        let data = try JSONEncoder().encode(run)
        XCTAssertNil(try JSONDecoder().decode(SavedAudioRun.self, from: data).deviceName)
        XCTAssertEqual(run.title(partCount: 1), "Microphone")
        XCTAssertThrowsError(try save(index: -1))
        XCTAssertThrowsError(try save(offset: .infinity))
    }
}
