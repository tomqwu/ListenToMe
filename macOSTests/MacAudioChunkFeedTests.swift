import XCTest

/// Generated local PCM exercises the production feed without Speech/model or microphone work.
final class MacAudioChunkFeedTests: XCTestCase {
    func testConvertedFileRetainsEveryFrameAndDistinctiveTail() throws {
        try AudioChunkFeedAssertions.conservation(self)
    }
    func testConvertedChunkTimestampsIncludeDrainedTails() throws {
        try AudioChunkFeedAssertions.timelines(self)
    }
    func testStopSuppressesPendingTailAndPreservesSource() throws {
        try AudioChunkFeedAssertions.cancellation(self)
    }
    func testEmptyAndUnreadableInputsPreserveSourceAndFailure() throws {
        try AudioChunkFeedAssertions.emptyAndErrors(self)
    }
}
