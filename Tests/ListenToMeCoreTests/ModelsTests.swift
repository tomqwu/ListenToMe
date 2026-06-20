import XCTest
@testable import ListenToMeCore

final class ModelsTests: XCTestCase {
    func testTranscriptSegmentStoresFields() {
        let id = UUID()
        let seg = TranscriptSegment(id: id, source: .others, text: "Hello",
                                    isFinal: true, start: 1.0, end: 2.0)
        XCTAssertEqual(seg.id, id)
        XCTAssertEqual(seg.source, .others)
        XCTAssertEqual(seg.text, "Hello")
        XCTAssertTrue(seg.isFinal)
        XCTAssertEqual(seg.start, 1.0)
        XCTAssertEqual(seg.end, 2.0)
    }

    func testAudioChunkStoresFields() {
        let chunk = AudioChunk(samples: [0.1, -0.2], sampleRate: 16000,
                               source: .you, timestamp: 3.0)
        XCTAssertEqual(chunk.samples, [0.1, -0.2])
        XCTAssertEqual(chunk.sampleRate, 16000)
        XCTAssertEqual(chunk.source, .you)
        XCTAssertEqual(chunk.timestamp, 3.0)
    }
}
