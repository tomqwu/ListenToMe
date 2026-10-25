import XCTest
@testable import ListenToMeCore

final class PlatformAdapterTests: XCTestCase {
    func testOldAudioCallbackCannotContaminateRestartedRunOrItsOffset() {
        let buffer = SpeakerAudioBuffer(maxSamples: 4)
        let old = buffer.currentGeneration()
        buffer.append(samples: [0.1, 0.2], sampleRate: 16_000, timestamp: 12, generation: old)
        let snapshot = buffer.snapshot()
        buffer.reset()
        buffer.append(samples: [9, 9], sampleRate: 16_000, timestamp: 99, generation: old)
        XCTAssertEqual(buffer.sampleCount, 0)
        XCTAssertEqual(buffer.startOffset, 0)
        buffer.append(samples: [0.3, 0.4], sampleRate: 16_000, timestamp: 25, generation: buffer.currentGeneration())
        XCTAssertEqual(buffer.snapshot().samples, [0.3, 0.4])
        XCTAssertEqual(buffer.startOffset, 25)
        XCTAssertEqual(snapshot.samples, [0.1, 0.2], "A held snapshot must survive reset independently")
    }

    func testRealConverterResamplesAndCapsInsteadOfGrowingWithoutBound() {
        let buffer = SpeakerAudioBuffer(maxSamples: 1000)
        let samples = (0..<4800).map { Float(sin(Double($0) * 2 * .pi * 440 / 48000)) }
        buffer.append(samples: samples, sampleRate: 48_000, timestamp: 2, generation: buffer.currentGeneration())
        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.samples.count, 1000)
        XCTAssertTrue(snapshot.samples.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(snapshot.samples.map { abs($0) }.max() ?? 0, 0.1)
        XCTAssertTrue(buffer.didTruncate)
        buffer.reset()
        XCTAssertFalse(buffer.didTruncate)
        XCTAssertEqual(buffer.retainedSampleCount, 0)
    }

    func testReferenceFilesDecodeRichTextAndReportOversizeAndMissingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rtf = root.appendingPathComponent("notes.rtf")
        try Data(#"{\rtf1\ansi Here is \b bold\b0 text.}"#.utf8).write(to: rtf)
        let large = root.appendingPathComponent("large.txt")
        try Data(repeating: 65, count: FileContextLoader.maxFileBytes + 1).write(to: large)
        let missing = root.appendingPathComponent("missing.md")
        let result = FileContextLoader.load([rtf, large, missing])
        XCTAssertEqual(result.documents.count, 1)
        XCTAssertTrue(result.documents[0].content.contains("bold"))
        XCTAssertFalse(result.documents[0].content.contains("\\rtf"))
        XCTAssertEqual(Set(result.skipped.map(\.name)), ["large.txt", "missing.md"])
    }
}
