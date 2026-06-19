import XCTest
@testable import ListenToMeCore

final class VADTests: XCTestCase {
    func testRMSOfSilenceIsZero() {
        XCTAssertEqual(rms(of: [0, 0, 0, 0]), 0, accuracy: 1e-6)
    }

    func testRMSOfConstantSignal() {
        XCTAssertEqual(rms(of: [0.5, -0.5, 0.5, -0.5]), 0.5, accuracy: 1e-6)
    }

    func testRMSOfEmptyIsZero() {
        XCTAssertEqual(rms(of: []), 0, accuracy: 1e-6)
    }

    func testSegmenterFiresAfterTrailingSilence() {
        var seg = VADSegmenter(speechThreshold: 0.1, silenceDuration: 0.5)
        // Speech starts at t=0.0, continues to 1.0, then silence.
        XCTAssertFalse(seg.process(rms: 0.3, at: 0.0))   // speech begins
        XCTAssertFalse(seg.process(rms: 0.3, at: 0.5))   // still speaking
        XCTAssertFalse(seg.process(rms: 0.0, at: 0.8))   // silence < 0.5s after last speech
        XCTAssertTrue(seg.process(rms: 0.0, at: 1.1))    // 0.6s of silence -> boundary
    }

    func testSegmenterDoesNotFireWithoutPriorSpeech() {
        var seg = VADSegmenter(speechThreshold: 0.1, silenceDuration: 0.5)
        XCTAssertFalse(seg.process(rms: 0.0, at: 0.0))
        XCTAssertFalse(seg.process(rms: 0.0, at: 10.0))
    }

    func testSegmenterFiresOncePerUtterance() {
        var seg = VADSegmenter(speechThreshold: 0.1, silenceDuration: 0.5)
        _ = seg.process(rms: 0.3, at: 0.0)
        XCTAssertTrue(seg.process(rms: 0.0, at: 0.6))    // boundary
        XCTAssertFalse(seg.process(rms: 0.0, at: 1.2))   // still silent, no double-fire
    }
}
