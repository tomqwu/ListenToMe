import AVFoundation
import Speech
import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileSpeechResultAdapterTests: XCTestCase {
    func testOrderedTextFinalityAndAudioRangesRemainIntact() async throws {
        let values = FixtureResult.values
        let feed = FixtureFeed(values)
        let prepared = MobilePreparedTranscriber(FixtureModule(feed), text: { $0.text })
        var received: [MobilePreparedTranscriber.Result] = []
        let exhausted = try await prepared.consume { received.append($0); return true }
        XCTAssertTrue(exhausted)
        XCTAssertEqual(received.map { String($0.text.characters) }, ["opening words", "final words"])
        XCTAssertEqual(received.map(\.isFinal), values.map(\.isFinal))
        XCTAssertNotEqual(values[0].isFinal, values[1].isFinal)
        XCTAssertEqual(received.map(\.range), values.map(\.range))
    }

    func testStoppedConsumerDoesNotReadAheadOrDropFinalizedText() async throws {
        let feed = FixtureFeed(FixtureResult.values)
        let prepared = MobilePreparedTranscriber(FixtureModule(feed), text: { $0.text })
        let exhausted = try await prepared.consume { _ in false }
        XCTAssertFalse(exhausted)
        // An eager producer would keep draining even though delivery stopped. Allow it to run.
        for _ in 0..<200 {
            if await feed.reads > 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let reads = await feed.reads
        XCTAssertEqual(reads, 1, "A stopped consumer must not accumulate a background result queue")
    }

    func testCancelledDeliveryDoesNotPullAnotherResult() async throws {
        let feed = FixtureFeed(FixtureResult.values)
        let prepared = MobilePreparedTranscriber(FixtureModule(feed), text: { $0.text })
        let task = Task {
            try await prepared.consume { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled delivery must stop consumption")
        } catch { XCTAssertTrue(error is CancellationError) }
        let reads = await feed.reads
        XCTAssertEqual(reads, 1)
    }
}

private struct FixtureResult: SpeechModuleResult, Sendable {
    let text: AttributedString
    let range: CMTimeRange
    let resultsFinalizationTime: CMTime
    static var values: [Self] {
        let range = CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 1000),
                               duration: CMTime(seconds: 3, preferredTimescale: 1000))
        return [Self(text: AttributedString("opening words"), range: range, resultsFinalizationTime: range.start),
                Self(text: AttributedString("final words"), range: range, resultsFinalizationTime: range.end)]
    }
}

private actor FixtureFeed {
    let values: [FixtureResult]
    private(set) var reads = 0
    init(_ values: [FixtureResult]) { self.values = values }
    func next() throws -> FixtureResult? {
        try Task.checkCancellation()
        defer { reads += 1 }
        return reads < values.count ? values[reads] : nil
    }
}

private struct FixtureResults: AsyncSequence, Sendable {
    typealias Element = FixtureResult
    let feed: FixtureFeed
    func makeAsyncIterator() -> Iterator { Iterator(feed: feed) }
    struct Iterator: AsyncIteratorProtocol {
        let feed: FixtureFeed
        mutating func next() async throws -> FixtureResult? { try await feed.next() }
    }
}

private final class FixtureModule: SpeechModule {
    typealias Result = FixtureResult
    typealias Results = FixtureResults
    let results: Results
    init(_ feed: FixtureFeed) { results = FixtureResults(feed: feed) }
    var availableCompatibleAudioFormats: [AVAudioFormat] { get async { [] } }
}
