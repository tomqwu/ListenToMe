import XCTest
@testable import ListenToMeCore

/// The phone's manifest for one Apple Watch recording waiting to be transcribed (issue #181).
final class WatchCaptureLedgerTests: XCTestCase {
    private let id = UUID()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let hour: TimeInterval = 3_600

    private func chunk(_ index: Int, isLast: Bool = false, duration: TimeInterval = 300) -> WatchChunkMetadata {
        WatchChunkMetadata(recordingID: id, index: index, startOffset: TimeInterval(index) * 300, duration: duration,
                           isLast: isLast, startedAt: start, watchBuild: "28")
    }

    private func ledger(_ indices: [Int], lastIndex: Int? = nil) -> WatchCaptureLedger {
        var ledger = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        for index in indices { ledger.receive(chunk(index, isLast: index == lastIndex), at: start) }
        return ledger
    }

    func testDuplicateChunkIsANoOp() {
        var ledger = ledger([0])
        let before = ledger
        XCTAssertFalse(ledger.receive(chunk(0), at: start.addingTimeInterval(hour)))
        XCTAssertEqual(ledger, before)
        XCTAssertTrue(ledger.receive(chunk(1), at: start))
        XCTAssertEqual(ledger.chunks.map(\.index), [0, 1])
        // Another recording's chunk or end marker never lands here.
        let other = WatchChunkMetadata(recordingID: UUID(), index: 5, startOffset: 1_500, duration: 300, isLast: true,
                                       startedAt: start, watchBuild: "28")
        let filed = ledger
        XCTAssertFalse(ledger.receive(other, at: start))
        ledger.receiveEnd(WatchRecordingEnd(recordingID: UUID(), startedAt: start, lastIndex: 9, unexpected: true),
                          at: start)
        XCTAssertEqual(ledger, filed)
    }

    func testOutOfOrderArrivalTranscribesOnlyTheContiguousPrefix() {
        var ledger = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        ledger.receive(chunk(2, isLast: true), at: start)
        ledger.receive(chunk(0), at: start)
        XCTAssertEqual(ledger.chunks.map(\.index), [0, 2], "Kept sorted by index")
        let batch = ledger.nextBatch(now: start.addingTimeInterval(60))
        XCTAssertEqual(batch, WatchLedgerBatch(indices: [0], newGaps: [], finishes: false))
    }

    func testMissingChunkWaits24HoursThenIsSkippedWithAGap() {
        let ledger = ledger([0, 2], lastIndex: 2)
        XCTAssertEqual(ledger.nextBatch(now: start.addingTimeInterval(23 * hour)),
                       WatchLedgerBatch(indices: [0], newGaps: [], finishes: false))
        XCTAssertEqual(ledger.nextBatch(now: start.addingTimeInterval(24 * hour)),
                       WatchLedgerBatch(indices: [0, 2], newGaps: [1...1], finishes: true))
    }

    func testFinishesWhenLastArrivesAndEverythingIsTranscribed() {
        var ledger = ledger([0, 1])
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [0, 1], newGaps: [], finishes: false))
        XCTAssertEqual(ledger.markTranscribed(through: 600), [0, 1])
        XCTAssertFalse(ledger.isFinished, "No last chunk yet")
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [], newGaps: [], finishes: false))
        ledger.receive(chunk(2, isLast: true), at: start)
        XCTAssertEqual(ledger.lastIndex, 2)
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [2], newGaps: [], finishes: true))
        XCTAssertFalse(ledger.isFinished)
        XCTAssertEqual(ledger.markTranscribed(through: 900), [2])
        XCTAssertTrue(ledger.isFinished)
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [], newGaps: [], finishes: true))
    }

    func testRecordingWithNoEndFinishesAfterTheTimeout() {
        var ledger = ledger([0, 1])
        ledger.markTranscribed(through: 600)
        XCTAssertFalse(ledger.nextBatch(now: start.addingTimeInterval(23 * hour)).finishes)
        XCTAssertEqual(ledger.nextBatch(now: start.addingTimeInterval(24 * hour)),
                       WatchLedgerBatch(indices: [], newGaps: [], finishes: true))
        // Activity resets the clock.
        ledger.receive(chunk(2), at: start.addingTimeInterval(20 * hour))
        XCTAssertEqual(ledger.nextBatch(now: start.addingTimeInterval(24 * hour)),
                       WatchLedgerBatch(indices: [2], newGaps: [], finishes: false))
        XCTAssertEqual(ledger.nextBatch(now: start.addingTimeInterval(44 * hour)),
                       WatchLedgerBatch(indices: [2], newGaps: [], finishes: true))
    }

    func testUnexpectedEndFinishesAndIsMarked() {
        var ledger = ledger([0, 1])
        ledger.receiveEnd(WatchRecordingEnd(recordingID: id, startedAt: start, lastIndex: 1, unexpected: true),
                          at: start)
        XCTAssertTrue(ledger.endedUnexpectedly)
        XCTAssertEqual(ledger.lastIndex, 1)
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [0, 1], newGaps: [], finishes: true))
        // An end marker can arrive before any chunk; its missing chunks still wait for the timeout.
        var early = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        early.receiveEnd(WatchRecordingEnd(recordingID: id, startedAt: start, lastIndex: 1, unexpected: false), at: start)
        XCTAssertFalse(early.endedUnexpectedly)
        XCTAssertEqual(early.nextBatch(now: start), WatchLedgerBatch(indices: [], newGaps: [], finishes: false))
        XCTAssertEqual(early.nextBatch(now: start.addingTimeInterval(24 * hour)),
                       WatchLedgerBatch(indices: [], newGaps: [0...1], finishes: true))
    }

    func testChunkAfterAFinishedRecordingExtendsIt() {
        var ledger = ledger([0, 1], lastIndex: 1)
        ledger.markTranscribed(through: 600)
        XCTAssertTrue(ledger.isFinished)
        // Continue after an interruption: more audio for the same recording.
        XCTAssertTrue(ledger.receive(chunk(2), at: start))
        XCTAssertFalse(ledger.isFinished)
        XCTAssertEqual(ledger.lastIndex, 1, "Only a last chunk extends the end")
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [2], newGaps: [], finishes: true))
        ledger.receive(chunk(3, isLast: true), at: start)
        XCTAssertEqual(ledger.lastIndex, 3)
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [2, 3], newGaps: [], finishes: true))
    }

    func testMarkTranscribedReturnsOnlyWhollyCoveredChunks() {
        var ledger = ledger([0, 1])
        XCTAssertEqual(ledger.markTranscribed(through: 310), [0])
        XCTAssertEqual(ledger.chunks.map(\.state), [.transcribed, .received])
        XCTAssertEqual(ledger.markTranscribed(through: 599.96), [1], "Within 0.05 s of the end counts")
        XCTAssertEqual(ledger.markTranscribed(through: 700), [], "Already transcribed chunks are not returned again")
    }

    func testTranscribedThroughNeverMovesBack() {
        var ledger = ledger([0, 1])
        ledger.markTranscribed(through: 450)
        ledger.markTranscribed(through: 100)
        XCTAssertEqual(ledger.transcribedThrough, 450)
        XCTAssertEqual(ledger.nextBatch(now: start).indices, [1])
    }

    func testFailedLedgerYieldsNothingUntilCleared() {
        var ledger = ledger([0, 1], lastIndex: 1)
        ledger.markFailed("The file is damaged.")
        XCTAssertEqual(ledger.failure, "The file is damaged.")
        XCTAssertEqual(ledger.nextBatch(now: start.addingTimeInterval(48 * hour)),
                       WatchLedgerBatch(indices: [], newGaps: [], finishes: false))
        ledger.clearFailure()
        XCTAssertNil(ledger.failure)
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [0, 1], newGaps: [], finishes: true))
    }

    func testNotedGapsAreNotReportedAgainAndLateChunksInThemAreIgnored() {
        var ledger = ledger([0, 2], lastIndex: 2)
        let later = start.addingTimeInterval(24 * hour)
        let batch = ledger.nextBatch(now: later)
        ledger.noteGaps(batch.newGaps)
        ledger.noteGaps(batch.newGaps)
        XCTAssertEqual(ledger.notedGaps, [1...1])
        XCTAssertEqual(ledger.nextBatch(now: later), WatchLedgerBatch(indices: [0, 2], newGaps: [], finishes: true))
        XCTAssertFalse(ledger.receive(chunk(1), at: later), "A chunk already written off as missing is ignored")
        ledger.markTranscribed(through: 900)
        XCTAssertTrue(ledger.isFinished)
        XCTAssertFalse(ledger.receive(chunk(0), at: later))
    }

    func testChunksBeforeWhatWasAlreadyTranscribedAreSettled() {
        // A recording reopened after it finished: the phone already holds text through 900 s.
        var ledger = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        ledger.receive(chunk(3, isLast: true), at: start)
        XCTAssertEqual(ledger.markTranscribed(through: 900), [])
        XCTAssertEqual(ledger.nextBatch(now: start), WatchLedgerBatch(indices: [3], newGaps: [], finishes: true))
        XCTAssertFalse(ledger.receive(chunk(1), at: start), "Audio already transcribed is not taken again")
        // A redelivered chunk wholly inside the transcribed time is marked done, so its audio can go.
        var redelivered = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        redelivered.receive(chunk(0, isLast: true), at: start)
        XCTAssertEqual(redelivered.markTranscribed(through: 900), [0])
        XCTAssertTrue(redelivered.isFinished)
    }

    func testGapMinutes() {
        var ledger = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        ledger.receive(chunk(0), at: start)
        ledger.receive(WatchChunkMetadata(recordingID: id, index: 3, startOffset: 870, duration: 300, isLast: true,
                                          startedAt: start, watchBuild: "28"), at: start)
        XCTAssertEqual(ledger.gapMinutes(1...2), 10, "(870 - 300) / 60 = 9.5, rounded")
        XCTAssertEqual(ledger.gapMinutes(4...5), 10, "No neighbour on one side: 5 minutes per chunk")
        var tight = WatchCaptureLedger(recordingID: id, startedAt: start, at: start)
        tight.receive(chunk(0), at: start)
        tight.receive(WatchChunkMetadata(recordingID: id, index: 2, startOffset: 305, duration: 300, isLast: true,
                                         startedAt: start, watchBuild: "28"), at: start)
        XCTAssertEqual(tight.gapMinutes(1...1), 1, "Never less than a minute")
    }

    func testCodableRoundTrip() throws {
        var ledger = ledger([0, 2], lastIndex: 2)
        ledger.receiveEnd(WatchRecordingEnd(recordingID: id, startedAt: start, lastIndex: 2, unexpected: true), at: start)
        ledger.markTranscribed(through: 300)
        ledger.noteGaps([1...1])
        ledger.markFailed("x")
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(WatchCaptureLedger.self, from: data), ledger)
        XCTAssertEqual(WatchCaptureLedger.gapTimeout, 86_400)
        XCTAssertEqual(ledger.chunks.first?.end, 300)
    }
}
