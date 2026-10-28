import AVFoundation
import CoreMedia
import Speech
import XCTest
import ListenToMeCore

private final class OneShotConversionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var didCancel = false

    func checkpoint() {
        let first = lock.withLock {
            guard !didCancel else { return false }
            didCancel = true
            return true
        }
        if first { withUnsafeCurrentTask { $0?.cancel() } }
    }
}

@MainActor
final class MacAnalyzerInputTests: XCTestCase {
    private enum Failure: Error { case notEnqueued }

    private func format() throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                   channels: 1, interleaved: false))
    }

    private func chunk(_ timestamp: Double, count: Int = 1_600, rate: Double = 16_000,
                       value: Float = 0.25, source: SpeakerSource = .others) -> AudioChunk {
        AudioChunk(samples: Array(repeating: value, count: count), sampleRate: rate,
                   source: source, timestamp: timestamp)
    }

    private func read(_ chunk: AudioChunk, through adapter: MacAnalyzerInputAdapter,
                      into continuation: AsyncStream<AnalyzerInput>.Continuation,
                      from iterator: inout AsyncStream<AnalyzerInput>.Iterator) async throws -> AnalyzerInput {
        guard try adapter.send(chunk, to: continuation) else { throw Failure.notEnqueued }
        let next = await iterator.next(isolation: #isolation)
        return try XCTUnwrap(next)
    }

    private func end(_ input: AnalyzerInput) throws -> CMTime {
        CMTimeAdd(try XCTUnwrap(input.bufferStartTime),
                  CMTime(value: CMTimeValue(input.buffer.frameLength),
                         timescale: CMTimeScale(input.buffer.format.sampleRate)))
    }

    func testTinyResampledChunksPreserveFirstOffsetAndContinueWithoutFailure() async throws {
        let adapter = MacAnalyzerInputAdapter(format: try format())
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        var emitted = 0
        for index in 0..<3001 {
            if try adapter.send(chunk(2 + Double(index) / 48_000, count: 1, rate: 48_000),
                                to: pair.continuation) { emitted += 1 }
        }
        pair.continuation.finish()
        var frames = 0
        var previousEnd: CMTime?
        for await input in pair.stream {
            let start = try XCTUnwrap(input.bufferStartTime)
            XCTAssertEqual(start.seconds, previousEnd?.seconds ?? 2, accuracy: 0.000_001)
            frames += Int(input.buffer.frameLength)
            previousEnd = try end(input)
        }
        XCTAssertEqual(emitted, 1000)
        XCTAssertEqual(frames, 1000, "Valid sub-frame input must accumulate in the native converter")
        adapter.stop()
        XCTAssertFalse(try adapter.send(chunk(3), to: pair.continuation))
    }

    func testGapBeforeFirstCompleteFrameUsesQuantizedAnchorOnce() async throws {
        let adapter = MacAnalyzerInputAdapter(format: try format())
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        defer { pair.continuation.finish() }
        var iterator = pair.stream.makeAsyncIterator()
        XCTAssertFalse(try adapter.send(chunk(2, count: 1, rate: 48_000), to: pair.continuation))
        XCTAssertFalse(try adapter.send(chunk(2 + 1.0 / 48_000, count: 1, rate: 48_000),
                                        to: pair.continuation))
        let nextRawStart = 2 + 2.0 / 48_000 + 0.75
        let first = try await read(chunk(nextRawStart, count: 4096, rate: 48_000), through: adapter,
                                   into: pair.continuation, from: &iterator)
        let start = try XCTUnwrap(first.bufferStartTime).seconds
        XCTAssertEqual(start, 2.75, accuracy: 0.000_001)
        XCTAssertLessThan(abs(nextRawStart - start), 1.0 / 16_000,
                          "A gap before any complete output frame is quantized to one frame")
        XCTAssertEqual(first.buffer.frameLength, 1366, "Retain the native sub-frame carry")
        let second = try await read(chunk(nextRawStart + 4096.0 / 48_000, count: 4096, rate: 48_000),
                                    through: adapter, into: pair.continuation, from: &iterator)
        XCTAssertEqual(try XCTUnwrap(second.bufferStartTime).seconds, try end(first).seconds,
                       accuracy: 0.000_001, "Apply the gap once, not once per later buffer")
    }

    func testConvertedLiveBuffersCannotOverlapAtAnalyzerBoundary() async throws {
        let format = try format()
        let adapter = MacAnalyzerInputAdapter(format: format)
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        defer { pair.continuation.finish() }
        var iterator = pair.stream.makeAsyncIterator()
        var previousEnd: CMTime?
        var capturedAt = 3.125
        var frames = 0
        for index in 0..<12 {
            let input = try await read(chunk(capturedAt, count: 4_096, rate: 44_100,
                                             value: Float(index + 1) / 20), through: adapter,
                                       into: pair.continuation, from: &iterator)
            let start = try XCTUnwrap(input.bufferStartTime)
            if let previousEnd {
                XCTAssertGreaterThanOrEqual(CMTimeCompare(start, previousEnd), 0,
                                            "Actual analyzer input cannot precede the prior converted end")
            } else { XCTAssertEqual(start.seconds, 3.125, accuracy: 0.000_001) }
            previousEnd = try end(input)
            capturedAt = try XCTUnwrap(previousEnd).seconds - 0.25 / format.sampleRate
            frames += Int(input.buffer.frameLength)
        }
        XCTAssertGreaterThan(frames, 17_000, "Keep converted frames instead of discarding overlapping buffers")
    }

    func testLongResamplingClockDriftPreservesFramesOrderAndLaterGap() async throws {
        for rate in [44_100.0, 48_000.0] {
            for drift in [-0.0002, 0.0002] {
                let adapter = MacAnalyzerInputAdapter(format: try format())
                let pair = AsyncStream<AnalyzerInput>.makeStream()
                var iterator = pair.stream.makeAsyncIterator()
                var rawStart = 7.25
                var previousEnd: CMTime?
                var previousRawEnd: Double?
                var frames = 0
                for index in 0..<2_000 {
                    if index == 1_200 { rawStart += 0.75 }
                    let value = Float(index % 100 + 1) / 128
                    let input = try await read(chunk(rawStart, count: 4_096, rate: rate, value: value),
                                               through: adapter, into: pair.continuation, from: &iterator)
                    let start = try XCTUnwrap(input.bufferStartTime)
                    if let previousEnd {
                        XCTAssertGreaterThanOrEqual(CMTimeCompare(start, previousEnd), 0)
                        let gap = CMTimeSubtract(start, previousEnd).seconds
                        XCTAssertEqual(gap, index == 1_200 ? rawStart - (previousRawEnd ?? 0) : 0,
                                       accuracy: 0.000_002, "Real gaps survive even after accumulated clock drift")
                    } else { XCTAssertEqual(start.seconds, 7.25, accuracy: 0.000_001) }
                    let nativeBuffer = input.buffer
                    let data = try XCTUnwrap(nativeBuffer.int16ChannelData)
                    let lastSample = withExtendedLifetime(nativeBuffer) {
                        data[0][Int(nativeBuffer.frameLength) - 1]
                    }
                    XCTAssertEqual(Double(lastSample),
                                   Double(value) * 32_768, accuracy: 3, "Converted chunks stay in source order")
                    frames += Int(input.buffer.frameLength)
                    previousEnd = try end(input)
                    previousRawEnd = rawStart + 4_096 / rate
                    rawStart += 4_096 / rate * (1 + drift)
                }
                XCTAssertEqual(Double(frames), 2_000 * 4_096 * 16_000 / rate, accuracy: 2,
                               "Every converted frame is retained across long resampling")
                pair.continuation.finish()
            }
        }
    }

    func testFirstOffsetsGapsAndSourcesAreIndependent() async throws {
        let mic = MacAnalyzerInputAdapter(format: try format())
        let system = MacAnalyzerInputAdapter(format: try format())
        let first = AsyncStream<AnalyzerInput>.makeStream()
        let second = AsyncStream<AnalyzerInput>.makeStream()
        defer { first.continuation.finish(); second.continuation.finish() }
        var micIterator = first.stream.makeAsyncIterator()
        var systemIterator = second.stream.makeAsyncIterator()
        let m1 = try await read(chunk(2, source: .you), through: mic, into: first.continuation, from: &micIterator)
        let s1 = try await read(chunk(8), through: system, into: second.continuation, from: &systemIterator)
        let m2 = try await read(chunk(2.9, source: .you), through: mic, into: first.continuation, from: &micIterator)
        XCTAssertEqual(try XCTUnwrap(m1.bufferStartTime).seconds, 2)
        XCTAssertEqual(try XCTUnwrap(s1.bufferStartTime).seconds, 8)
        XCTAssertEqual(try XCTUnwrap(m2.bufferStartTime).seconds, 2.9, accuracy: 0.000_001)
    }

    func testInvalidOrBackwardInputCannotAdvanceTheCurrentPipeline() async throws {
        let adapter = MacAnalyzerInputAdapter(format: try format())
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        defer { pair.continuation.finish() }
        var iterator = pair.stream.makeAsyncIterator()
        let first = try await read(chunk(4), through: adapter, into: pair.continuation, from: &iterator)
        for stamp in [Double.nan, .infinity, -1, 4, 1] {
            XCTAssertThrowsError(try adapter.send(chunk(stamp), to: pair.continuation))
        }
        for rate in [Double.nan, .infinity, .greatestFiniteMagnitude, 0, -1] {
            XCTAssertThrowsError(try adapter.send(chunk(4.1, rate: rate), to: pair.continuation))
        }
        XCTAssertFalse(try adapter.send(chunk(4.1, count: 0), to: pair.continuation))
        let next = try await read(chunk(4.1), through: adapter, into: pair.continuation, from: &iterator)
        XCTAssertEqual(CMTimeCompare(try XCTUnwrap(next.bufferStartTime), try end(first)), 0)
    }

    func testCancellationTerminationAndFreshPipelineCannotEnqueueLateAudio() async throws {
        let adapter = MacAnalyzerInputAdapter(format: try format())
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        let cancelled = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            return try adapter.send(self.chunk(99), to: pair.continuation)
        }
        cancelled.cancel()
        let accepted = try await cancelled.value
        XCTAssertFalse(accepted)
        var iterator = pair.stream.makeAsyncIterator()
        let first = try await read(chunk(3), through: adapter, into: pair.continuation, from: &iterator)
        XCTAssertEqual(try XCTUnwrap(first.bufferStartTime).seconds, 3)
        adapter.stop()
        XCTAssertFalse(try adapter.send(chunk(3.1), to: pair.continuation))
        pair.continuation.finish()
        let exhausted = await iterator.next(isolation: #isolation)
        XCTAssertNil(exhausted)
        let fresh = MacAnalyzerInputAdapter(format: try format())
        let live = AsyncStream<AnalyzerInput>.makeStream()
        let ended = AsyncStream<AnalyzerInput>.makeStream()
        ended.continuation.finish()
        XCTAssertFalse(try fresh.send(chunk(50), to: ended.continuation))
        XCTAssertFalse(try fresh.send(chunk(50), to: live.continuation))
        let replacement = MacAnalyzerInputAdapter(format: try format())
        var liveIterator = live.stream.makeAsyncIterator()
        let replacementInput = try await read(chunk(1), through: replacement, into: live.continuation, from: &liveIterator)
        XCTAssertEqual(try XCTUnwrap(replacementInput.bufferStartTime).seconds, 1)
        live.continuation.finish()
    }

    func testUnsupportedNativeFormatAndBackpressureFailBeforeLateAudio() async throws {
        if #available(macOS 27.0, *) {
            let unsafeFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                      sampleRate: 16_000, channels: 1, interleaved: false))
            let unsupported = MacAnalyzerInputAdapter(format: unsafeFormat)
            let invalid = AsyncStream<AnalyzerInput>.makeStream()
            XCTAssertThrowsError(try unsupported.send(chunk(0), to: invalid.continuation))
            invalid.continuation.finish()
            var invalidIterator = invalid.stream.makeAsyncIterator()
            let empty = await invalidIterator.next(isolation: #isolation)
            XCTAssertNil(empty, "Unsupported PCM must not reach the framework's precondition")
        }
        let adapter = MacAnalyzerInputAdapter(format: try format())
        let bounded = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(1))
        XCTAssertTrue(try adapter.send(chunk(0), to: bounded.continuation))
        XCTAssertThrowsError(try adapter.send(chunk(0.1), to: bounded.continuation))
        XCTAssertFalse(try adapter.send(chunk(0.2), to: bounded.continuation))
        bounded.continuation.finish()
        var iterator = bounded.stream.makeAsyncIterator()
        let kept = await iterator.next(isolation: #isolation)
        XCTAssertEqual(try XCTUnwrap(kept?.bufferStartTime).seconds, 0)
        let noLateInput = await iterator.next(isolation: #isolation)
        XCTAssertNil(noLateInput)
    }

    func testCancellationDuringConversionDiscardsTheAdvancedConverter() async throws {
        let cancellation = OneShotConversionCancellation()
        let adapter = MacAnalyzerInputAdapter(format: try format(), conversionCheckpoint: cancellation.checkpoint)
        let pair = AsyncStream<AnalyzerInput>.makeStream()
        let task = Task { @MainActor in
            try adapter.send(self.chunk(9, count: 4_096, rate: 44_100), to: pair.continuation)
        }
        let accepted = try await task.value
        XCTAssertFalse(accepted)
        XCTAssertFalse(Task.isCancelled, "The conversion checkpoint cancels only the owned task")
        XCTAssertFalse(try adapter.send(chunk(9, count: 4_096, rate: 44_100), to: pair.continuation),
                       "An adapter that consumed cancelled audio cannot reuse its converter")
        pair.continuation.finish()
        var iterator = pair.stream.makeAsyncIterator()
        let late = await iterator.next(isolation: #isolation)
        XCTAssertNil(late)
        let replacement = MacAnalyzerInputAdapter(format: try format())
        let fresh = AsyncStream<AnalyzerInput>.makeStream()
        var freshIterator = fresh.stream.makeAsyncIterator()
        let first = try await read(chunk(1, count: 4_096, rate: 44_100), through: replacement,
                                   into: fresh.continuation, from: &freshIterator)
        XCTAssertEqual(try XCTUnwrap(first.bufferStartTime).seconds, 1)
        fresh.continuation.finish()
    }
}
