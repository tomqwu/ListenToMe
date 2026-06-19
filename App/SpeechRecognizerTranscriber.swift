import Foundation
import Speech
import AVFoundation
import ListenToMeCore

/// On-device transcription: one SFSpeechRecognizer + recognition task per source.
/// VAD detects utterance boundaries; at a boundary the request is ended (which makes the
/// recognizer emit a FINAL result) and, once that task completes, a fresh task is started.
/// Tasks for a source never overlap (the Speech framework rejects overlap with error 1100),
/// and the brief gap between ending one task and starting the next falls during the detected
/// silence, so little audio is lost. An actor so all shared state access is serialized.
actor SpeechRecognizerTranscriber: Transcribing {
    nonisolated let segments: AsyncStream<TranscriptSegment>
    private nonisolated let continuation: AsyncStream<TranscriptSegment>.Continuation

    private var states: [SpeakerSource: SourceState] = [:]
    private var authorized = false
    private var stopped = false

    init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { await self?.setAuthorized(status == .authorized) }
        }
    }

    private func setAuthorized(_ value: Bool) { authorized = value }

    func feed(_ chunk: AudioChunk) async {
        guard authorized, !stopped else { return }
        guard let state = states[chunk.source] ?? startTask(for: chunk.source) else { return }
        states[chunk.source] = state

        if state.awaitingFinal {
            // Carry onset audio across the finalization gap; replayed (through VAD) into the next task.
            state.pendingChunks.append(chunk)
            if state.pendingChunks.count > 64 { state.pendingChunks.removeFirst() }
            return
        }

        let boundary = state.segmenter.process(rms: rms(of: chunk.samples), at: chunk.timestamp)
        if let buffer = makeBuffer(from: chunk) { state.request.append(buffer) }
        if boundary {
            // End the utterance -> recognizer emits a final result; await it before the next task.
            state.awaitingFinal = true
            state.request.endAudio()
        }
    }

    func finish() async {
        stopped = true
        for state in states.values { state.request.endAudio() }
        for _ in 0..<30 {
            if states.values.allSatisfy({ $0.done }) { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        states.removeAll()
        continuation.finish()
    }

    // MARK: - Per-source recognition

    private final class SourceState {
        let recognizer: SFSpeechRecognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        var task: SFSpeechRecognitionTask?
        var segmenter = VADSegmenter(speechThreshold: 0.02, silenceDuration: 0.8)
        var awaitingFinal = false
        var done = false
        var pendingChunks: [AudioChunk] = []
        init(recognizer: SFSpeechRecognizer) {
            self.recognizer = recognizer
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
        }
    }

    private func startTask(for source: SpeakerSource) -> SourceState? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { return nil }
        let state = SourceState(recognizer: recognizer)
        state.task = recognizer.recognitionTask(with: state.request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.continuation.yield(TranscriptSegment(
                    source: source,
                    text: result.bestTranscription.formattedString,
                    isFinal: result.isFinal,
                    start: 0,
                    end: 0
                ))
            }
            if error != nil {
                Task { await self.taskFailed(source) }
            } else if result?.isFinal ?? false {
                Task { await self.taskEnded(source) }
            }
        }
        return state
    }

    /// A source's utterance finalized normally: start a fresh task and replay any audio buffered
    /// during the finalization gap (through the new VAD so its speech state stays consistent).
    private func taskEnded(_ source: SpeakerSource) {
        let pending = states[source]?.pendingChunks ?? []
        states[source]?.done = true
        guard !stopped else { return }
        guard let fresh = startTask(for: source) else {
            states[source] = nil
            return
        }
        var sawBoundary = false
        for chunk in pending {
            if fresh.segmenter.process(rms: rms(of: chunk.samples), at: chunk.timestamp) {
                sawBoundary = true
            }
            if let buffer = makeBuffer(from: chunk) { fresh.request.append(buffer) }
        }
        states[source] = fresh
        if sawBoundary {
            // Replayed audio contained a complete utterance; finalize it now.
            fresh.awaitingFinal = true
            fresh.request.endAudio()
        }
    }

    /// A source's task errored. Tear it down WITHOUT an immediate restart so a persistent startup
    /// error can't spin; the next incoming chunk for this source lazily creates a fresh task.
    private func taskFailed(_ source: SpeakerSource) {
        states[source]?.done = true
        states[source] = nil
    }

    private func makeBuffer(from chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard !chunk.samples.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: chunk.sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(chunk.samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        for (index, sample) in chunk.samples.enumerated() {
            buffer.floatChannelData![0][index] = sample
        }
        return buffer
    }
}
