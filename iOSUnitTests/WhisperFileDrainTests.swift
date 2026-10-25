import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

final class WhisperFileDrainTests: XCTestCase {
    func testFinishTranscribesBufferedFinalUtterance() async {
        let engine = WhisperKitTranscriber(decodeFixture: { _ in "Final buffered speech" })
        await engine.prepare()
        for tick in 0...10 {
            await engine.feed(AudioChunk(samples: Array(repeating: 0.2, count: 1_600), sampleRate: 16_000,
                                         source: .others, timestamp: Double(tick) / 10))
        }
        await engine.finish()
        var lines: [TranscriptSegment] = []
        for await line in engine.segments { lines.append(line) }
        XCTAssertEqual(lines.map(\.text), ["Final buffered speech"])
        XCTAssertEqual(lines.first?.source, .others)
        XCTAssertEqual(lines.first?.end, 1)
    }

    func testFinishDrainsQueuedBatchesAfterAcceleratedFileFeed() async {
        let engine = WhisperKitTranscriber(decodeFixture: { _ in
            try await Task.sleep(for: .milliseconds(30))
            return "Decoded batch"
        })
        await engine.prepare()
        for tick in 0..<80 {
            await engine.feed(AudioChunk(samples: Array(repeating: (tick / 10) % 2 == 0 ? 0.2 : 0, count: 1_600),
                                         sampleRate: 16_000, source: .others, timestamp: Double(tick) / 10))
        }
        await engine.finish()
        var lines: [TranscriptSegment] = []
        for await line in engine.segments { lines.append(line) }
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertEqual(lines.last?.end ?? 0, 6.9, accuracy: 0.001)
    }
}
