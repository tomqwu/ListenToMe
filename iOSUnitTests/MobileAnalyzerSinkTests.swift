import AVFoundation
import Speech
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Issue #197: changing the transcription language must not lose microphone audio, and the copies for
/// speakers and language detection must stay on the transcript's timeline. The sink and the replay run
/// in the simulator; only the speech model itself needs a device.
@MainActor
final class MobileAnalyzerSinkTests: XCTestCase {
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1,
                                       interleaved: true)!

    private func chunk(seconds: Double, rate: Double = 48_000) -> AudioChunk {
        AudioChunk(samples: [Float](repeating: 0.1, count: Int(seconds * rate)), sampleRate: rate, source: .you,
                   timestamp: 0)
    }

    private func drain(_ stream: AsyncStream<AnalyzerInput>, _ continuation: AsyncStream<AnalyzerInput>.Continuation)
        async -> [AnalyzerInput] {
        continuation.finish()
        var inputs: [AnalyzerInput] = []
        for await input in stream { inputs.append(input) }
        return inputs
    }

    func testAudioDuringASwitchIsParkedThenSentToTheNewAnalyzerAndCopiedOnce() async {
        let (oldStream, oldInput) = AsyncStream<AnalyzerInput>.makeStream()
        let speakers = SpeakerAudioBuffer(), language = SpeakerAudioBuffer()
        let sink = AnalyzerSink(input: oldInput, destination: format, speakerAudio: speakers,
                                speakerGeneration: speakers.currentGeneration(), languageAudio: language,
                                languageGeneration: language.currentGeneration())
        XCTAssertTrue(sink.canConvert(sampleRate: 48_000))
        XCTAssertEqual(sink.deliver(chunk(seconds: 1)), .accepted)
        XCTAssertEqual(sink.deliver(chunk(seconds: 1)), .accepted)
        let cut = sink.hold()
        XCTAssertEqual(cut.deliveredSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(cut.languageSamples, language.sampleCount)
        XCTAssertEqual(sink.deliver(chunk(seconds: 0.5)), .accepted, "Audio during the switch is parked, not lost")

        let (newStream, newInput) = AsyncStream<AnalyzerInput>.makeStream()
        sink.resume(input: newInput, destination: format, continueAt: cut.deliveredSeconds)
        XCTAssertEqual(sink.deliver(chunk(seconds: 1)), .accepted)

        let old = await drain(oldStream, oldInput)
        let new = await drain(newStream, newInput)
        XCTAssertEqual(old.count, 2)
        XCTAssertEqual(new.count, 2, "The parked chunk goes first, then live audio")
        XCTAssertEqual(new.first?.bufferStartTime?.seconds ?? -1, 2, accuracy: 0.001,
                       "Without a replay the new analyzer continues the old timeline")
        XCTAssertNil(new.last?.bufferStartTime)
        XCTAssertEqual(Double(speakers.sampleCount) / 16_000, 3.5, accuracy: 0.01, "Every chunk is copied exactly once")
        XCTAssertEqual(speakers.sampleCount, language.sampleCount)
    }

    func testAnUnconvertibleRateIsReportedAndNotCopied() {
        let (_, input) = AsyncStream<AnalyzerInput>.makeStream()
        let speakers = SpeakerAudioBuffer()
        let sink = AnalyzerSink(input: input, destination: format, speakerAudio: speakers,
                                speakerGeneration: speakers.currentGeneration(), languageAudio: nil,
                                languageGeneration: 0)
        XCTAssertFalse(sink.canConvert(sampleRate: 0))
        let silent = AudioChunk(samples: [0.1], sampleRate: 0, source: .you, timestamp: 0)
        XCTAssertEqual(sink.deliver(silent), .unconvertible)
        XCTAssertEqual(speakers.sampleCount, 0)
    }

    func testADroppedChunkIsNotCopied() {
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let language = SpeakerAudioBuffer()
        let sink = AnalyzerSink(input: input, destination: format, speakerAudio: nil, speakerGeneration: 0,
                                languageAudio: language, languageGeneration: language.currentGeneration())
        XCTAssertEqual(sink.deliver(chunk(seconds: 1)), .accepted)
        XCTAssertEqual(sink.deliver(chunk(seconds: 1)), .dropped)
        XCTAssertEqual(Double(language.sampleCount) / 16_000, 1, accuracy: 0.01)
        withExtendedLifetime(stream) {}   // a released stream terminates instead of dropping
    }

    func testReplayFeedsTheRecordingFromItsStartInTwoSecondBuffers() async {
        let buffer = SpeakerAudioBuffer()
        buffer.append(samples: [Float](repeating: 0.1, count: 16_000 * 5), sampleRate: 16_000, timestamp: 0,
                      generation: buffer.currentGeneration())
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        XCTAssertTrue(MobileRecorder.replay(buffer, through: 16_000 * 5, into: input, format: format))
        let inputs = await drain(stream, input)
        XCTAssertEqual(inputs.map { Int($0.buffer.frameLength) }.reduce(0, +), 16_000 * 5, "All five seconds, once")
        XCTAssertEqual(inputs.count, 3)
        XCTAssertNil(inputs.first?.bufferStartTime, "A replay from the start needs no stamp, as in #197")
    }

    /// Issue #199: a re-check switch transcribes only the span since the change, on the recording's timeline.
    func testAReplayFromPartWayStampsItsStartAndFeedsOnlyThatSpan() async {
        let buffer = SpeakerAudioBuffer()
        buffer.append(samples: [Float](repeating: 0.1, count: 16_000 * 30), sampleRate: 16_000, timestamp: 0,
                      generation: buffer.currentGeneration())
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        XCTAssertTrue(MobileRecorder.replay(buffer, from: 16_000 * 21, through: 16_000 * 26, into: input,
                                            format: format))
        let inputs = await drain(stream, input)
        XCTAssertEqual(inputs.map { Int($0.buffer.frameLength) }.reduce(0, +), 16_000 * 5)
        XCTAssertEqual(inputs.first?.bufferStartTime?.seconds ?? -1, 21, accuracy: 0.001)
        XCTAssertEqual(inputs.dropFirst().compactMap(\.bufferStartTime).count, 0, "Later buffers follow on")
    }

    /// Issue #199: the language copy keeps only the trailing two minutes, released in whole blocks.
    func testTheLanguageCopyKeepsOnlyTheTrailingTwoMinutes() async {
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        let language = SpeakerAudioBuffer(maxSamples: .max)
        let sink = AnalyzerSink(input: input, destination: format, speakerAudio: nil, speakerGeneration: 0,
                                languageAudio: language, languageGeneration: language.currentGeneration())
        for _ in 0..<135 { XCTAssertEqual(sink.deliver(chunk(seconds: 1, rate: 16_000)), .accepted) }
        XCTAssertEqual(language.sampleCount, 135 * 16_000, "Sample indexes stay on the recording's timeline")
        XCTAssertEqual(language.heldFrom, 10, "One ten-second block released, never the last two minutes")
        XCTAssertGreaterThanOrEqual(language.retainedSampleCount, LanguageRecheckPolicy.retainedSamples)
        _ = await drain(stream, input)
    }

    func testReplayRefusesAudioItNoLongerHolds() {
        let (_, input) = AsyncStream<AnalyzerInput>.makeStream()
        let empty = SpeakerAudioBuffer()
        XCTAssertFalse(MobileRecorder.replay(empty, through: 16_000, into: input, format: format))
        let capped = SpeakerAudioBuffer(maxSamples: 16_000)
        capped.append(samples: [Float](repeating: 0, count: 32_000), sampleRate: 16_000, timestamp: 0,
                      generation: capped.currentGeneration())
        XCTAssertTrue(capped.didTruncate)
        XCTAssertFalse(MobileRecorder.replay(capped, through: 16_000, into: input, format: format),
                       "A truncated recording cannot be replayed onto the same timeline")
        let trailing = SpeakerAudioBuffer()
        trailing.append(samples: [Float](repeating: 0, count: 16_000 * 30), sampleRate: 16_000, timestamp: 0,
                        generation: trailing.currentGeneration())
        trailing.discardAudio(before: 16_000 * 20)
        XCTAssertFalse(MobileRecorder.replay(trailing, from: 16_000 * 5, through: 16_000 * 30, into: input,
                                             format: format), "Audio already released cannot be heard again")
        XCTAssertTrue(MobileRecorder.replay(trailing, from: 16_000 * 25, through: 16_000 * 30, into: input,
                                            format: format))
        XCTAssertFalse(MobileRecorder.replay(trailing, from: 16_000 * 30, through: 16_000 * 30, into: input,
                                             format: format), "Nothing to hear again")
    }
}
