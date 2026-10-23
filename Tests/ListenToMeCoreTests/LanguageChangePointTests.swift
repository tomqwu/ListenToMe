import XCTest
@testable import ListenToMeCore

/// Issue #199: once a re-check confirms another language, find where it changed and where transcribing
/// again can start, so only that part of the recording is transcribed again.
final class LanguageChangePointTests: XCTestCase {
    private typealias Policy = LanguageRecheckPolicy

    func testChunksNeedSpeechAndAreCapped() {
        let speech: (Range<TimeInterval>) -> TimeInterval = { $0.lowerBound >= 20 && $0.lowerBound < 30 ? 2 : 8 }
        XCTAssertEqual(Policy.scanChunks(0..<45, speech: speech), [0..<10, 10..<20, 30..<40, 40..<45])
        XCTAssertEqual(Policy.scanChunks(0..<3, speech: speech), [], "Too short to say anything")
        let long = Policy.scanChunks(0..<200) { _ in 10 }
        XCTAssertEqual(long.count, Policy.maximumScanChunks)
        XCTAssertEqual(long.first, 80..<90, "The latest chunks are kept")
    }

    func testVerdictsReadEachChunk() {
        XCTAssertEqual(Policy.verdict(detected: "fr", probability: 0.6, current: "en-US", target: "fr-FR"), .target)
        XCTAssertEqual(Policy.verdict(detected: "en", probability: 0.6, current: "en-US", target: "fr-FR"), .current)
        XCTAssertEqual(Policy.verdict(detected: "fr", probability: 0.3, current: "en-US", target: "fr-FR"), .unclear)
        XCTAssertEqual(Policy.verdict(detected: "es", probability: 0.9, current: "en-US", target: "fr-FR"), .unclear)
        XCTAssertEqual(Policy.verdict(detected: "fr", probability: .nan, current: "en-US", target: "fr-FR"), .unclear)
    }

    func testTheChangeIsAfterTheLastChunkInTheOldLanguage() {
        let span: Range<TimeInterval> = 50..<120
        func at(_ start: TimeInterval) -> Range<TimeInterval> { start..<(start + 10) }
        XCTAssertEqual(Policy.changePoint(in: span, scanned: [(at(50), .current), (at(60), .current),
                                                              (at(70), .unclear), (at(80), .target)]), 70)
        XCTAssertEqual(Policy.changePoint(in: span, scanned: [(at(60), .target), (at(100), .current)]), 110,
                       "The latest chunk still in the old language: only what follows it is transcribed again")
        XCTAssertEqual(Policy.changePoint(in: 50..<105, scanned: [(at(100), .current)]), 105,
                       "Never past the span")
        XCTAssertEqual(Policy.changePoint(in: span, scanned: [(at(60), .target)]), 50, "No old chunk: the span's start")
        XCTAssertEqual(Policy.changePoint(in: span, scanned: []), 50)
    }

    /// Review of #212, finding 3: speech in a chunk that was not checked (too little speech) between the
    /// last old-language chunk and the next checked one is transcribed again, not left in the old language.
    func testSpeechBetweenTheLastOldChunkAndTheNextCheckedOneIsTranscribedAgain() {
        func at(_ start: TimeInterval) -> Range<TimeInterval> { start..<(start + 10) }
        XCTAssertEqual(Policy.changePoint(in: 50..<120, scanned: [(at(80), .target), (at(60), .current)]), 70,
                       "Order does not matter, and 70–80 (not checked) is heard again")
    }

    func testTheReplayStartsAtALineBoundaryWithinTheHeldAudio() {
        let lines: [Range<TimeInterval>] = [40..<48, 50..<58, 58.5..<66]
        XCTAssertEqual(Policy.replayStart(desired: 49, retainedFrom: 0, lines: lines), 49)
        XCTAssertEqual(Policy.replayStart(desired: 55, retainedFrom: 0, lines: lines), 50,
                       "A line spanning the change is heard again whole")
        XCTAssertEqual(Policy.replayStart(desired: 20, retainedFrom: 52, lines: lines), 58,
                       "A line whose start is gone is left as it is")
        XCTAssertEqual(Policy.replayStart(desired: 0, retainedFrom: 0, lines: []), 0)
        XCTAssertEqual(Policy.replayStart(desired: 60, retainedFrom: 0, lines: [50..<62, 55..<70]), 50,
                       "Overlapping lines move it back again")
    }

    func testAReplayNeverStartsInTheBlockAboutToBeReleased() {
        XCTAssertEqual(Policy.replayFloor(captured: 90, heldFrom: 0), 0)
        XCTAssertEqual(Policy.replayFloor(captured: 119, heldFrom: 0), 0)
        XCTAssertEqual(Policy.replayFloor(captured: 125, heldFrom: 0), 10, "The first block goes at 130 s")
        XCTAssertEqual(Policy.replayFloor(captured: 129, heldFrom: 10), 10)
        XCTAssertEqual(Policy.replayFloor(captured: 135, heldFrom: 10), 20, "The 10–20 s block goes at 140 s")
        XCTAssertEqual(Policy.replayFloor(captured: 150, heldFrom: 30), 40)
    }

    func testTimeRangesBecomeHeldSampleRanges() {
        XCTAssertEqual(Policy.samples(0.5..<2, total: 100_000), 8_000..<32_000)
        XCTAssertEqual(Policy.samples(5..<10, total: 100_000), 80_000..<100_000)
        XCTAssertEqual(Policy.samples(10..<20, total: 100_000), 100_000..<100_000)
        XCTAssertEqual(Policy.samples(-1..<1, total: -5), 0..<0)
        XCTAssertEqual(Policy.retainedSamples, 1_920_000)
    }
}
