import Foundation
import Speech
import AVFoundation
import ListenToMeCore

/// On-device transcription using the macOS 26 SpeechAnalyzer/SpeechTranscriber API.
/// One analyzer + transcriber per SpeakerSource, so both channels transcribe concurrently
/// (SpeechAnalyzer has no single-active-recognition limit, unlike SFSpeechRecognizer).
/// Actor-isolated for safe shared-state access.
@available(macOS 26.0, *)
actor SpeechAnalyzerTranscriber: Transcribing {
    nonisolated let segments: AsyncStream<TranscriptSegment>
    private nonisolated let continuation: AsyncStream<TranscriptSegment>.Continuation

    private var pipelines: [SpeakerSource: Pipeline] = [:]
    private var stopped = false

    init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }

    func feed(_ chunk: AudioChunk) async {
        guard !stopped else { return }
        let pipeline: Pipeline
        if let existing = pipelines[chunk.source] {
            pipeline = existing
        } else {
            guard let created = await makePipeline(for: chunk.source) else { return }
            guard !stopped else {
                // stop() ran during async setup — tear down the just-created pipeline.
                created.inputContinuation.finish()
                try? await created.analyzer.finalizeAndFinishThroughEndOfInput()
                created.resultsTask.cancel()
                return
            }
            pipelines[chunk.source] = created
            pipeline = created
        }
        guard let buffer = pipeline.convert(chunk) else { return }
        pipeline.inputContinuation.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async {
        stopped = true
        for pipeline in pipelines.values {
            pipeline.inputContinuation.finish()
            try? await pipeline.analyzer.finalizeAndFinishThroughEndOfInput()
            await pipeline.resultsTask.value   // drain finalized results; the stream ends after finalize
        }
        pipelines.removeAll()
        continuation.finish()
    }

    private func makePipeline(for source: SpeakerSource) async -> Pipeline? {
        let transcriber = SpeechTranscriber(
            locale: Locale.current,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
        } catch {
            // Proceed: model may already be installed; if not, start() will surface an error.
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            return nil
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

        let id = UUID()
        let cont = continuation
        let resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    Self.emit(result, from: source, to: cont)
                }
            } catch {
                // results stream errored
            }
            // Stream ended (error or completion): drop this pipeline so the next feed recreates it.
            await self?.resultsEnded(source: source, id: id)
        }
        do {
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            resultsTask.cancel()
            inputContinuation.finish()
            return nil
        }
        return Pipeline(
            id: id,
            transcriber: transcriber,
            analyzer: analyzer,
            inputContinuation: inputContinuation,
            format: format,
            resultsTask: resultsTask
        )
    }

    /// A source's results stream ended. If we're still running and this is the current pipeline
    /// for the source, drop it so the next `feed` lazily recreates a fresh analyzer.
    private func resultsEnded(source: SpeakerSource, id: UUID) {
        guard !stopped, pipelines[source]?.id == id else { return }
        pipelines[source] = nil
    }

    /// Forward a transcriber result to the segment stream.
    /// Finals are emitted only when non-empty; volatile hypotheses always flow through
    /// (an empty volatile result revokes the current partial).
    private static func emit(
        _ result: SpeechTranscriber.Result,
        from source: SpeakerSource,
        to cont: AsyncStream<TranscriptSegment>.Continuation
    ) {
        let text = String(result.text.characters)
        if result.isFinal, text.isEmpty { return }
        cont.yield(TranscriptSegment(
            source: source,
            text: text,
            isFinal: result.isFinal,
            start: 0,
            end: 0
        ))
    }
}

// MARK: - Pipeline

@available(macOS 26.0, *)
private final class Pipeline: @unchecked Sendable {
    let id: UUID
    let transcriber: SpeechTranscriber
    let analyzer: SpeechAnalyzer
    let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    let format: AVAudioFormat
    let resultsTask: Task<Void, Never>
    private var converter: AVAudioConverter?

    init(
        id: UUID,
        transcriber: SpeechTranscriber,
        analyzer: SpeechAnalyzer,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        format: AVAudioFormat,
        resultsTask: Task<Void, Never>
    ) {
        self.id = id
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = inputContinuation
        self.format = format
        self.resultsTask = resultsTask
    }

    /// Convert a mono-Float32 chunk into the analyzer's expected format.
    func convert(_ chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard !chunk.samples.isEmpty,
              let srcFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: chunk.sampleRate,
                channels: 1,
                interleaved: false
              ),
              let srcBuf = AVAudioPCMBuffer(
                pcmFormat: srcFormat,
                frameCapacity: AVAudioFrameCount(chunk.samples.count)
              ) else { return nil }
        srcBuf.frameLength = AVAudioFrameCount(chunk.samples.count)
        for (index, sample) in chunk.samples.enumerated() {
            srcBuf.floatChannelData![0][index] = sample
        }
        if srcFormat == format { return srcBuf }
        if converter == nil { converter = AVAudioConverter(from: srcFormat, to: format) }
        guard let converter else { return nil }
        let ratio = format.sampleRate / srcFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(chunk.samples.count) * ratio) + 1_024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var convError: NSError?
        converter.convert(to: outBuf, error: &convError) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData; return srcBuf
        }
        if convError != nil { return nil }
        return outBuf
    }
}
