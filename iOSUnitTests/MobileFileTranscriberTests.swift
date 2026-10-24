import AVFoundation
import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// On-device transcription of Apple Watch audio files (issue #181). Speech runs only on a device,
/// like live recording; in the simulator these tests check the refusal instead.
@MainActor
final class MobileFileTranscriberTests: XCTestCase {
    private func fixture(_ index: Int) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "watch-chunk-\(index)", withExtension: "m4a"))
    }

    private func duration(_ url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private func chunks() throws -> [WatchAudioChunk] {
        let first = try fixture(0), second = try fixture(1)
        let firstDuration = try duration(first)
        return [WatchAudioChunk(index: 0, url: first, startOffset: 0, duration: firstDuration),
                WatchAudioChunk(index: 1, url: second, startOffset: firstDuration, duration: try duration(second))]
    }

    func testFixturesAreMono16kAAC() throws {
        for index in 0...1 {
            let file = try AVAudioFile(forReading: try fixture(index))
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
            XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
            XCTAssertEqual(try duration(try fixture(index)), 1.8, accuracy: 0.5)
        }
    }

    func testTranscribesOrderedChunksWithRecordingRelativeTimes() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Speech runs only on a device, like live recording.")
        #else
        let chunks = try chunks()
        var segments: [TranscriptSegment] = []
        try await MobileFileTranscriber().transcribe(chunks, locale: Locale(identifier: "en_US")) { segments.append($0) }
        let text = segments.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("budget"), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Sarah"), text)
        for segment in segments where segment.text.localizedCaseInsensitiveContains("Sarah") {
            XCTAssertGreaterThanOrEqual(segment.start, chunks[0].duration - 0.5, "\(segment)")
        }
        XCTAssertTrue(segments.allSatisfy { $0.isFinal && $0.source == .you })
        #endif
    }

    func testCancellationThrowsAndDeliversNothingAfterIt() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Speech runs only on a device, like live recording.")
        #else
        let chunks = try chunks()
        var cancelled = false
        var afterCancel = 0
        let transcriber = MobileFileTranscriber()
        let task = Task { @MainActor in
            try await transcriber.transcribe(chunks, locale: Locale(identifier: "en_US")) { _ in
                if cancelled { afterCancel += 1 }
            }
        }
        task.cancel()
        cancelled = true
        do {
            try await task.value
            XCTFail("A cancelled transcription must throw")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertEqual(afterCancel, 0)
        #endif
    }

    func testSimulatorRefusesLikeLiveRecording() async throws {
        #if targetEnvironment(simulator)
        do {
            try await MobileFileTranscriber().transcribe(try chunks(), locale: Locale(identifier: "en_US")) { _ in }
            XCTFail("The simulator cannot transcribe")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("requires a physical iPhone or iPad"),
                          error.localizedDescription)
        }
        #else
        throw XCTSkip("Checks the simulator refusal.")
        #endif
    }

    /// A chunk claiming to start inside audio already fed starts where that audio ended instead, so
    /// the analyzer's time never steps backward. A real gap keeps its start.
    func testFeedNeverStepsTimeBackward() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1,
                                                 interleaved: false))
        let first = try fixture(0)
        let firstDuration = try duration(first)
        let feed = ChunkFeed(chunks: [
            WatchAudioChunk(index: 0, url: first, startOffset: 0, duration: firstDuration),
            WatchAudioChunk(index: 1, url: try fixture(1), startOffset: 1, duration: 1.6),
            WatchAudioChunk(index: 2, url: first, startOffset: 100, duration: firstDuration),
        ], format: format)
        var stamps: [TimeInterval] = []
        var buffers = 0
        while let input = feed.next() {
            buffers += 1
            if let start = input.bufferStartTime { stamps.append(start.seconds) }
        }
        XCTAssertNil(feed.failure)
        XCTAssertGreaterThan(buffers, 3)
        XCTAssertEqual(stamps.count, 3, "One stamp per chunk")
        XCTAssertEqual(stamps[0], 0, accuracy: 0.001)
        XCTAssertEqual(stamps[1], firstDuration, accuracy: 0.05, "Not 1 s: that audio was already fed")
        XCTAssertEqual(stamps[2], 100, accuracy: 0.001)
    }

    func testNoChunksIsANoOp() async throws {
        var calls = 0
        try await MobileFileTranscriber().transcribe([], locale: Locale(identifier: "en_US")) { _ in calls += 1 }
        XCTAssertEqual(calls, 0)
    }
}
