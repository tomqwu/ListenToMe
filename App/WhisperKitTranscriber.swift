import Foundation
import AVFoundation
import ListenToMeCore
import WhisperKit

/// Opt-in multilingual transcription via WhisperKit (https://github.com/argmaxinc/WhisperKit).
///
/// WhisperKit is a batch (whole-utterance) transcriber, not a streaming one: we buffer each
/// source's incoming mono-Float32 samples, run the Core `VADSegmenter` over per-chunk RMS to find
/// end-of-utterance boundaries, and at each boundary transcribe the buffered audio for that source
/// and emit a single FINAL `TranscriptSegment`. This trades live partials for Whisper's stronger
/// multilingual / code-switching quality.
///
/// The model is downloaded lazily on first audio (a few hundred MB for "base"); failures are
/// logged via NSLog and the transcriber degrades to a no-op rather than crashing the session.
/// An actor so all shared buffer/state access is serialized.
actor WhisperKitTranscriber: Transcribing {
    nonisolated let segments: AsyncStream<TranscriptSegment>
    private nonisolated let continuation: AsyncStream<TranscriptSegment>.Continuation

    /// WhisperKit consumes 16 kHz mono Float32 audio.
    private static let whisperSampleRate: Double = 16_000
    /// Skip transcribing utterances shorter than this many 16 kHz samples (~0.25 s) — Whisper
    /// tends to hallucinate on near-silent fragments.
    private static let minUtteranceSamples = 4_000

    /// Small multilingual model. Other valid choices: "tiny", "small". "base" balances quality
    /// and the first-run download size.
    private static let modelName = "base"

    private let language: String?

    private var kitBox: KitBox?
    /// nil before the first init attempt; set once we've tried (so we don't retry a hard failure
    /// on every chunk and spin the download).
    private var initAttempted = false
    private var stopped = false

    private var states: [SpeakerSource: SourceState] = [:]

    /// - Parameter locale: maps to WhisperKit's `language` decoding option. When the locale's
    ///   language can't be determined (e.g. system "Auto"), we leave it nil and enable Whisper's
    ///   own language detection — the right setting for multilingual / code-switching speech.
    init(locale: Locale = .current) {
        self.language = Self.whisperLanguageCode(for: locale)
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }

    func feed(_ chunk: ListenToMeCore.AudioChunk) async {
        guard !stopped else { return }
        let box = await ensureWhisperKit()
        guard box != nil, !stopped else { return }

        let state = states[chunk.source] ?? SourceState()
        states[chunk.source] = state

        // Resample to 16 kHz mono and buffer.
        if let resampled = state.resample(chunk, to: Self.whisperSampleRate) {
            state.buffer.append(contentsOf: resampled)
        }

        let boundary = state.segmenter.process(rms: rms(of: chunk.samples), at: chunk.timestamp)
        if boundary {
            await transcribeBuffered(for: chunk.source)
        }
    }

    func finish() async {
        stopped = true
        for source in states.keys {
            await transcribeBuffered(for: source)
        }
        states.removeAll()
        continuation.finish()
    }

    // MARK: - Transcription

    /// Transcribe (and clear) the buffered audio for a source, emitting a final segment.
    /// Guards against overlapping transcribe calls per source: while one is in flight the buffer
    /// keeps accumulating and is picked up by the next boundary / finish.
    private func transcribeBuffered(for source: SpeakerSource) async {
        guard let box = kitBox, let state = states[source], !state.transcribing else { return }
        guard state.buffer.count >= Self.minUtteranceSamples else {
            // Too short to be real speech; drop it so it can't accumulate stale onset noise.
            state.buffer.removeAll(keepingCapacity: true)
            return
        }
        let audio = state.buffer
        state.buffer.removeAll(keepingCapacity: true)
        state.transcribing = true
        defer { state.transcribing = false }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            detectLanguage: language == nil
        )
        do {
            let results = try await box.kit.transcribe(audioArray: audio, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            continuation.yield(TranscriptSegment(
                source: source,
                text: text,
                isFinal: true,
                start: 0,
                end: 0
            ))
        } catch {
            NSLog("WhisperKitTranscriber: transcribe failed for \(source.rawValue): \(error.localizedDescription)")
        }
    }

    // MARK: - Lazy model load

    /// Lazily create the WhisperKit instance, downloading the model on first call. Returns nil and
    /// logs on failure; only one init is attempted for the lifetime of the transcriber.
    private func ensureWhisperKit() async -> KitBox? {
        if let kitBox { return kitBox }
        guard !initAttempted else { return nil }
        initAttempted = true
        do {
            let kit = try await WhisperKit(
                model: Self.modelName,
                verbose: false,
                logLevel: .error,
                download: true
            )
            let box = KitBox(kit: kit)
            kitBox = box
            return box
        } catch {
            NSLog("WhisperKitTranscriber: model load failed (\(Self.modelName)): \(error.localizedDescription)")
            return nil
        }
    }

    /// `WhisperKit` is a non-Sendable class but is internally thread-safe for `transcribe`. Boxing
    /// it as `@unchecked Sendable` lets the actor hand the instance to WhisperKit's nonisolated
    /// async `transcribe` without Swift 6 sending-violations (mirrors the `Pipeline` box pattern
    /// in SpeechAnalyzerTranscriber). We serialize our own calls per source via `transcribing`.
    private final class KitBox: @unchecked Sendable {
        let kit: WhisperKit
        init(kit: WhisperKit) { self.kit = kit }
    }

    // MARK: - Locale → Whisper language

    /// Map a `Locale` to a Whisper two-letter language code (e.g. "en", "zh", "ja"). Returns nil
    /// when no specific language is known, so the caller enables Whisper's auto-detection.
    private static func whisperLanguageCode(for locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier, !code.isEmpty else { return nil }
        return code.lowercased()
    }

    // MARK: - Per-source state

    private final class SourceState {
        var buffer: [Float] = []
        var segmenter = VADSegmenter(speechThreshold: 0.02, silenceDuration: 0.8)
        var transcribing = false
        private var converter: AVAudioConverter?

        /// Resample a mono-Float32 chunk to the target rate, returning the converted samples.
        /// Passes through unchanged when the chunk is already at the target rate.
        func resample(_ chunk: ListenToMeCore.AudioChunk, to targetRate: Double) -> [Float]? {
            guard !chunk.samples.isEmpty else { return nil }
            if chunk.sampleRate == targetRate { return chunk.samples }
            guard let srcFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: chunk.sampleRate,
                    channels: 1,
                    interleaved: false),
                  let dstFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: targetRate,
                    channels: 1,
                    interleaved: false),
                  let srcBuf = AVAudioPCMBuffer(
                    pcmFormat: srcFormat,
                    frameCapacity: AVAudioFrameCount(chunk.samples.count))
            else { return nil }
            srcBuf.frameLength = AVAudioFrameCount(chunk.samples.count)
            for (index, sample) in chunk.samples.enumerated() {
                srcBuf.floatChannelData![0][index] = sample
            }
            if converter == nil { converter = AVAudioConverter(from: srcFormat, to: dstFormat) }
            guard let converter else { return nil }
            let ratio = targetRate / chunk.sampleRate
            let capacity = AVAudioFrameCount(Double(chunk.samples.count) * ratio) + 1_024
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else { return nil }
            var consumed = false
            var convError: NSError?
            converter.convert(to: outBuf, error: &convError) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true; status.pointee = .haveData; return srcBuf
            }
            if convError != nil { return nil }
            let count = Int(outBuf.frameLength)
            guard count > 0, let channel = outBuf.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(start: channel, count: count))
        }
    }
}
