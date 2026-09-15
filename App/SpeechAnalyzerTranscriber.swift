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
    nonisolated let statusUpdates: AsyncStream<String>
    private nonisolated let statusContinuation: AsyncStream<String>.Continuation
    nonisolated let segments: AsyncStream<TranscriptSegment>
    private nonisolated let continuation: AsyncStream<TranscriptSegment>.Continuation

    private var pipelines: [SpeakerSource: Pipeline] = [:]
    private var stopped = false
    private var failedSources = Set<SpeakerSource>()
    private let locale: Locale
    /// Whether `prepare()` should warm the system-audio (`.others`) pipeline. False when Screen
    /// Recording isn't available, so we don't leave an idle analyzer plus a results task running
    /// for a channel that will never receive audio (issue #147). `feed` still builds the pipeline
    /// lazily if system audio does start flowing, so a false negative only costs the warm-up.
    private let warmSystemAudio: Bool

    init(locale: Locale = .current, warmSystemAudio: Bool = true) {
        self.locale = locale
        self.warmSystemAudio = warmSystemAudio
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
        (statusUpdates, statusContinuation) = AsyncStream<String>.makeStream()
    }

    /// Builds the live channels' pipelines up front (asset check/download, locale resolution,
    /// analyzer start) so `feed` is a non-blocking hand-off and the opening seconds of a meeting
    /// aren't lost while the first-run speech model downloads. The system-audio channel is warmed
    /// only when `warmSystemAudio` says it can actually deliver audio, so a Screen-Recording-denied
    /// session doesn't carry an idle analyzer and results task for the whole run (issue #147).
    /// Cancellable: the session cancels this when the user stops, closes the window or quits
    /// during the download.
    func prepare() async {
        let sources: [SpeakerSource] = warmSystemAudio ? [.you, .others] : [.you]
        for source in sources {
            guard !stopped, !Task.isCancelled else { return }
            _ = await ensurePipeline(for: source)
        }
    }

    func feed(_ chunk: AudioChunk) async {
        guard !stopped, !failedSources.contains(chunk.source) else { return }
        // Normally already warm from prepare(); this also recreates a pipeline whose results
        // stream ended mid-session.
        guard let pipeline = await ensurePipeline(for: chunk.source) else { return }
        guard let buffer = pipeline.convert(chunk) else { return }
        pipeline.inputContinuation.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async {
        stopped = true
        for pipeline in pipelines.values {
            pipeline.inputContinuation.finish()
            do { try await pipeline.analyzer.finalizeAndFinishThroughEndOfInput() } catch {
                statusContinuation.yield("Transcript finalization failed: \(error.localizedDescription)")
            }
            await pipeline.resultsTask.value   // drain finalized results; the stream ends after finalize
        }
        pipelines.removeAll()
        continuation.finish()
        statusContinuation.finish()
    }

    /// Returns the live pipeline for a source, building it on first use. Returns nil when setup
    /// failed, was cancelled, or the transcriber stopped while setup was in flight.
    private func ensurePipeline(for source: SpeakerSource) async -> Pipeline? {
        if let existing = pipelines[source] { return existing }
        guard !failedSources.contains(source) else { return nil }
        guard let created = await makePipeline(for: source) else { return nil }
        guard !stopped else {
            // stop() ran during async setup — tear down the just-created pipeline.
            created.inputContinuation.finish()
            try? await created.analyzer.finalizeAndFinishThroughEndOfInput()
            created.resultsTask.cancel()
            return nil
        }
        pipelines[source] = created
        return created
    }

    private func makePipeline(for source: SpeakerSource) async -> Pipeline? {
        guard SpeechTranscriber.isAvailable else {
            statusContinuation.yield("SpeechAnalyzer is unavailable on this Mac. Choose another engine in Settings.")
            failedSources.insert(source)
            return nil
        }
        statusContinuation.yield("Transcription: preparing on-device speech model…")
        let (resolvedLocale, fellBack) = await Self.supportedLocale(for: locale)
        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
        } catch {
            statusContinuation.yield("Speech model installation failed: \(error.localizedDescription). Stop and restart to retry.")
            failedSources.insert(source)
            return nil
        }
        // The user stopped/closed/quit during the (possibly multi-minute) download: abandon setup
        // without latching a failure, so a later run can warm the now-installed model.
        guard !Task.isCancelled, !stopped else { return nil }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            statusContinuation.yield("Speech model unavailable. Check language and restart.")
            failedSources.insert(source)
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
                self?.statusContinuation.yield("Transcription failed: \(error.localizedDescription). Stop and restart.")
                await self?.markFailed(source)
            }
            // Stream ended (error or completion): drop this pipeline so the next feed recreates it.
            await self?.resultsEnded(source: source, id: id)
        }
        do {
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            statusContinuation.yield("Transcription could not start: \(error.localizedDescription)")
            failedSources.insert(source)
            resultsTask.cancel()
            inputContinuation.finish()
            return nil
        }
        // A silent en-US fallback is the one status worth keeping on screen: it explains an
        // otherwise inexplicable transcript, and the user can act on it (#136).
        statusContinuation.yield(fellBack
            ? Self.fallbackStatus(requested: locale, resolved: resolvedLocale)
            : TranscriptionLocaleStatus.running(resolvedLocale.identifier))
        return Pipeline(
            id: id,
            transcriber: transcriber,
            analyzer: analyzer,
            inputContinuation: inputContinuation,
            format: format,
            resultsTask: resultsTask
        )
    }

    /// Resolves a requested locale to one `SpeechTranscriber` actually supports (equivalent
    /// language/region where possible), falling back to en-US, so an unsupported choice doesn't
    /// build a dead module that yields an empty transcript.
    ///
    /// - Returns: the resolved locale and whether this was a *fallback* — i.e. the requested
    ///   language is not supported at all and the transcript will come out in another language.
    ///   The caller surfaces that, because silently transcribing a pt-BR meeting in en-US produces
    ///   English-looking nonsense with nothing on screen to explain it (issue #136).
    private static func supportedLocale(for requested: Locale) async -> (locale: Locale, fellBack: Bool) {
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return (equivalent, false)
        }
        let supported = await SpeechTranscriber.supportedLocales
        let resolved = supported.first(where: { $0.identifier(.bcp47) == "en-US" })
            ?? supported.first ?? requested
        return (resolved, true)
    }

    /// Human-readable "your language isn't available" line for the status rail. Wording lives in
    /// Core (`TranscriptionLocaleStatus`) so it is unit-tested.
    static func fallbackStatus(requested: Locale, resolved: Locale) -> String {
        TranscriptionLocaleStatus.fallback(requested: requested.identifier(.bcp47),
                                           resolved: resolved.identifier(.bcp47))
    }

    /// A source's results stream ended. If we're still running and this is the current pipeline
    /// for the source, drop it so the next `feed` lazily recreates a fresh analyzer.
    private func markFailed(_ source: SpeakerSource) { failedSources.insert(source) }

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
