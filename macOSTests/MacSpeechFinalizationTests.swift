import AVFoundation
import Speech
import XCTest
import ListenToMeCore

/// Runs the actual native analyzer with installed language assets; no capture or user data.
@MainActor
final class MacSpeechFinalizationTests: XCTestCase {
    private func prepared() async throws -> SpeechAnalyzerTranscriber {
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == "en-US" }) else {
            throw XCTSkip("Install the English (US) speech model before native lifecycle acceptance")
        }
        let transcriber = SpeechAnalyzerTranscriber(locale: Locale(identifier: "en-US"))
        await transcriber.prepare()
        return transcriber
    }

    func testPreparedChannelsWithoutAudioFinishAndCloseResults() async throws {
        let transcriber = try await prepared()
        let statuses = Task { () -> [String] in
            var received: [String] = []
            for await status in transcriber.statusUpdates { received.append(status) }
            return received
        }
        let completed = expectation(description: "Prepared silent channels finish without holding Start disabled")
        let task = Task {
            await transcriber.finish()
            for await _ in transcriber.segments { XCTFail("No audio must produce no transcript") }
            let received = await statuses.value
            XCTAssertFalse(received.contains { $0.localizedCaseInsensitiveContains("failed") },
                           "Intentional unused-channel cancellation is not a recognition failure: \(received)")
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 10)
        task.cancel()
    }

    func testOneUsedChannelDoesNotLeaveTheOtherPreparedChannelOpen() async throws {
        for source: SpeakerSource in [.others, .you] {
            let transcriber = try await prepared()
            await transcriber.feed(AudioChunk(samples: Array(repeating: 0, count: 16_000),
                                              sampleRate: 16_000, source: source, timestamp: 0))
            let completed = expectation(description: "Single-channel input reaches idle and closes results: \(source)")
            let task = Task {
                await transcriber.finish()
                for await segment in transcriber.segments { XCTAssertEqual(segment.source, source) }
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 15)
            task.cancel()
        }
    }

    func testCancelledPreparedImportClosesResultsAndReturns() async throws {
        let transcriber = try await prepared()
        let completed = expectation(description: "Cancel releases prepared import and result drain")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await transcriber.finish()
            for await _ in transcriber.segments { XCTFail("Cancelled empty import must have no transcript") }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 10)
        task.cancel()
    }

    func testSingleChannelImportRetainsFinalWordsAndTimestampsAtEOF() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Imports/orion.aiff")
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        for source: SpeakerSource in [.others, .you] {
            let transcriber = try await prepared()
            var finals: [TranscriptSegment] = []
            let drain = Task {
                for await segment in transcriber.segments where segment.isFinal { finals.append(segment) }
            }
            for offset in stride(from: 0, to: samples.count, by: 4096) {
                await transcriber.feed(AudioChunk(samples: Array(samples[offset..<min(offset + 4096, samples.count)]),
                    sampleRate: file.processingFormat.sampleRate, source: source,
                    timestamp: Double(offset) / file.processingFormat.sampleRate))
            }
            let completed = expectation(description: "EOF returns after all final words: \(source)")
            let task = Task {
                await transcriber.finish()
                await drain.value
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 20)
            task.cancel(); drain.cancel()
            let text = finals.map(\.text).joined(separator: " ").lowercased()
            XCTAssertTrue(text.contains("orion"), "Preserve the first spoken sentence")
            XCTAssertTrue(text.contains("project folder"), "Preserve the final words flushed at EOF")
            XCTAssertTrue(finals.allSatisfy { $0.source == source })
            XCTAssertGreaterThan(finals.last?.end ?? 0, 9, "Retain the recording's final audio time")
        }
    }
}
