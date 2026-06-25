import Foundation
import AVFoundation
import ListenToMeCore
import WhisperKit

/// Opt-in multilingual transcription via WhisperKit (https://github.com/argmaxinc/WhisperKit).
///
/// WhisperKit is a batch (whole-utterance) transcriber, not a streaming one: we buffer each
/// source's incoming mono-Float32 samples (only once speech is detected, with a short pre-roll so
/// the onset isn't clipped), run the Core `VADSegmenter` over per-chunk RMS to find end-of-utterance
/// boundaries, and at each boundary transcribe the buffered audio for that source and emit a single
/// FINAL `TranscriptSegment`. This trades live partials for Whisper's stronger multilingual /
/// code-switching quality.
///
/// Transcription runs on a per-source `Task`, never on the `feed` path, so the capture pump is
/// never blocked while WhisperKit batches an utterance (it buffers only the newest chunks). Only
/// one transcription runs per source at a time; audio arriving during one is queued and picked up
/// when it finishes. `finish()` flushes remaining audio and drains all in-flight tasks before
/// closing the stream so the last utterance is never lost.
///
/// The model downloads on first audio in a background Task that `feed` never awaits (so the
/// download can't drop audio); per-source transcription Tasks await the model before transcribing.
/// Load failures are logged via NSLog and the transcriber degrades to a no-op rather than crashing
/// the session. An actor so all shared buffer/state access is serialized.
actor WhisperKitTranscriber: Transcribing {
    nonisolated let segments: AsyncStream<TranscriptSegment>
    private nonisolated let continuation: AsyncStream<TranscriptSegment>.Continuation

    /// WhisperKit consumes 16 kHz mono Float32 audio.
    private static let whisperSampleRate: Double = 16_000
    /// Skip transcribing utterances shorter than this many 16 kHz samples (~0.25 s) — Whisper
    /// tends to hallucinate on near-silent fragments.
    private static let minUtteranceSamples = 4_000
    /// Pre-roll kept (in 16 kHz samples, ~0.3 s) so the onset of speech isn't clipped: we don't
    /// buffer indefinite pre-speech silence, but we retain a short tail of recent audio so the
    /// first word that crosses the VAD speech threshold isn't lost.
    private static let prerollSamples = 4_800

    /// Small multilingual model. Other valid choices: "tiny", "small". "base" balances quality
    /// and the first-run download size.
    private static let modelName = "base"

    private let language: String?

    /// The model load runs as a background Task kicked off on first audio and is awaited only inside
    /// per-source transcription Tasks (off the feed path), so the initial download never blocks the
    /// capture pump. Resolves to nil on a hard load failure (transcriber degrades to a no-op).
    private var loadTask: Task<KitBox?, Never>?
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
        // Kick off the (potentially long) model download in the background without awaiting it, so
        // audio keeps accumulating while the model loads; transcription Tasks await it later.
        startModelLoadIfNeeded()

        let state = states[chunk.source] ?? SourceState()
        states[chunk.source] = state

        let energy = rms(of: chunk.samples)
        let resampled = state.resample(chunk, to: Self.whisperSampleRate)

        if energy >= state.segmenter.speechThreshold {
            state.heardSpeech = true
        }

        if let resampled {
            if state.heardSpeech {
                state.buffer.append(contentsOf: resampled)
            } else {
                // No speech yet: don't buffer indefinite silence; keep only a short pre-roll so the
                // onset of the next utterance isn't clipped.
                state.preroll.append(contentsOf: resampled)
                if state.preroll.count > Self.prerollSamples {
                    state.preroll.removeFirst(state.preroll.count - Self.prerollSamples)
                }
            }
        }

        let boundary = state.segmenter.process(rms: energy, at: chunk.timestamp)
        if boundary {
            // Snapshot+clear and transcribe off the feed path so the capture pump never blocks on a
            // WhisperKit batch (DualChannelCapture buffers only the newest chunks).
            startTranscription(for: chunk.source)
        }
    }

    func finish() async {
        stopped = true
        // Flush any remaining buffered speech per source, then drain every in-flight transcription
        // so the last utterance's final segment is emitted before the stream closes.
        for source in states.keys {
            startTranscription(for: source)
        }
        // Drain in a loop: a finishing task may chain a queued follow-up (pending audio captured
        // during a long transcription), so keep awaiting until no source has a live task.
        while true {
            let inFlight = states.values.compactMap(\.task)
            if inFlight.isEmpty { break }
            for task in inFlight {
                await task.value
            }
        }
        states.removeAll()
        continuation.finish()
    }

    // MARK: - Transcription

    /// Snapshot+clear the source's buffered speech and transcribe it on a separate Task so `feed`
    /// returns immediately and keeps buffering incoming chunks. Only one transcription runs per
    /// source at a time: if one is already in flight, this marks more audio pending so the in-flight
    /// task picks it up on completion, never blocking the capture pump.
    private func startTranscription(for source: SpeakerSource) {
        guard let state = states[source] else { return }
        // Only transcribe when real speech was buffered — never send a preroll-only silence tail to
        // WhisperKit (it hallucinates text on near-silent audio).
        guard !state.buffer.isEmpty else { return }
        // After a boundary we may resume buffering pre-speech silence for the next utterance.
        state.heardSpeech = false

        let audio = state.takeBuffer()
        guard audio.count >= Self.minUtteranceSamples else { return }   // too short to be real speech

        guard state.task == nil else {
            // A transcription is already running for this source; let it pick up the next snapshot.
            state.pending.append(contentsOf: audio)
            return
        }
        state.task = makeTranscriptionTask(for: source, audio: audio)
    }

    /// Build the Task that transcribes one utterance and, on completion, chains any audio that
    /// accumulated while it ran (so boundaries during a long transcription aren't dropped).
    private func makeTranscriptionTask(for source: SpeakerSource, audio: [Float]) -> Task<Void, Never> {
        Task { [weak self] in
            await self?.transcribe(audio, for: source)
            await self?.transcriptionFinished(for: source)
        }
    }

    /// Run one batch transcription and emit its final segment. Off the actor's feed path: awaits the
    /// model becoming ready (so the first-run download doesn't block `feed`) before transcribing.
    private func transcribe(_ audio: [Float], for source: SpeakerSource) async {
        guard let box = await loadTask?.value else { return }   // model unavailable — degrade to no-op
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

    /// A source's transcription Task finished: clear the slot and, if a boundary fired while it ran,
    /// kick off the queued audio so no utterance is lost.
    private func transcriptionFinished(for source: SpeakerSource) {
        guard let state = states[source] else { return }
        state.task = nil
        guard !state.pending.isEmpty else { return }
        let next = state.pending
        state.pending.removeAll(keepingCapacity: true)
        guard next.count >= Self.minUtteranceSamples else { return }
        state.task = makeTranscriptionTask(for: source, audio: next)
    }

    // MARK: - Lazy model load

    /// Start the WhisperKit model download/load once, in the background. The Task is awaited only by
    /// per-source transcription Tasks, never by `feed`, so the initial download can't drop audio.
    /// Resolves to nil and logs on a hard failure (only attempted once per transcriber lifetime).
    private func startModelLoadIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task {
            do {
                let kit = try await WhisperKit(
                    model: Self.modelName,
                    verbose: false,
                    logLevel: .error,
                    download: true
                )
                return KitBox(kit: kit)
            } catch {
                NSLog("WhisperKitTranscriber: model load failed (\(Self.modelName)): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// `WhisperKit` is a non-Sendable class but is internally thread-safe for `transcribe`. Boxing
    /// it as `@unchecked Sendable` lets the actor hand the instance to WhisperKit's nonisolated
    /// async `transcribe` without Swift 6 sending-violations (mirrors the `Pipeline` box pattern
    /// in SpeechAnalyzerTranscriber). We serialize our own calls per source via `state.task`.
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
        /// Audio for the in-progress utterance (16 kHz). Empty until speech is first heard.
        var buffer: [Float] = []
        /// Short ring of recent pre-speech audio, prepended to `buffer` when speech starts so the
        /// utterance onset isn't clipped.
        var preroll: [Float] = []
        /// Audio that arrived while a transcription Task was already running for this source; picked
        /// up when that task finishes so boundaries during a long transcription aren't lost.
        var pending: [Float] = []
        /// True once a chunk for this source has crossed the VAD speech threshold; reset at each
        /// boundary. Gates buffering so we never accumulate indefinite pre-speech silence.
        var heardSpeech = false
        /// The single in-flight transcription Task for this source, or nil when idle.
        var task: Task<Void, Never>?
        var segmenter = VADSegmenter(speechThreshold: 0.02, silenceDuration: 0.8)
        private var converter: AVAudioConverter?

        /// Snapshot the current utterance (pre-roll + buffered speech) and clear both for the next.
        func takeBuffer() -> [Float] {
            let audio = preroll + buffer
            buffer.removeAll(keepingCapacity: true)
            preroll.removeAll(keepingCapacity: true)
            return audio
        }

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
