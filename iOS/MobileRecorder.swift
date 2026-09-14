import AVFoundation
import Speech
import ListenToMeCore

/// Foreground microphone capture. Model preparation completes before the audio tap starts.
@MainActor
protocol MobileRecording: AnyObject {
    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws
    func stop() async throws
    /// Rebuild the tap, converter and engine after the input route or engine configuration changed.
    /// The analyzer and the transcript so far survive; only capture restarts.
    func reconfigure() async throws
}

extension MobileRecording {
    func reconfigure() async throws {}
}

/// Audio lost before the transcriber sees it. One dropped buffer is a hiccup, not a reason to end a
/// meeting, so drops are tolerated until this much continuous audio has been lost.
private let tolerableLostSeconds = 2.0

@MainActor
final class MobileRecorder: MobileRecording {
    private lazy var engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var audio: AsyncStream<AudioChunk>.Continuation?
    private var feedTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var hasTap = false
    private var analyzerFormat: AVAudioFormat?
    private var report: (@MainActor (String) -> Void)?
    private var configurationObserver: (any NSObjectProtocol)?

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        #if targetEnvironment(simulator)
        throw RecordingError.message("Live transcription is unavailable in the iPhone simulator. " +
            "Run ListenToMe on a physical iPhone or iPad to record. Microphone permission will not fix this; " +
            "notes, history and export still work here.")
        #else
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecordingError.message("Microphone access is off. Enable ListenToMe in Settings → Privacy & Security → Microphone.")
        }
        try Task.checkCancellation()
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw RecordingError.message("On-device transcription is unavailable for this device or language. Try another language.")
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw RecordingError.message("The speech model has no supported audio format.")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        self.analyzerFormat = format
        self.report = onFailure
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        let (inputs, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.input = input
        try await analyzer.start(inputSequence: inputs)
        try Task.checkCancellation()
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    guard !result.isFinal || !text.isEmpty else { continue }
                    onSegment(TranscriptSegment(source: .you, text: text, isFinal: result.isFinal,
                                                start: result.range.start.seconds, end: result.range.end.seconds,
                                                speakerName: "Microphone"))
                }
                if engine.isRunning { onFailure("Transcription ended. Recording stopped; captured text is kept.") }
            } catch {
                if !Task.isCancelled { onFailure("Transcription stopped: \(error.localizedDescription)") }
            }
        }
        try startCapture()
        observeConfigurationChanges()
        #endif
    }

    /// A newly connected headset changes the input sample rate, which stops AVAudioEngine and posts
    /// this notification. Without it the tap simply stops firing and the meeting is lost in silence.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.restartAfterConfigurationChange() }
            }
    }

    private func restartAfterConfigurationChange() async {
        guard hasTap else { return }
        do { try await reconfigure() }
        catch {
            report?("Recording stopped: the microphone changed and capture could not restart " +
                    "(\(error.localizedDescription)). Captured text is kept.")
        }
    }

    func reconfigure() async throws {
        guard analyzerFormat != nil, hasTap || engine.isRunning else { return }
        await stopCapture()
        try startCapture()
    }

    /// Install the tap and the conversion pipeline for whatever input the engine currently has.
    /// Conversion runs on a detached task: a main-thread stall must never cost audio.
    private func startCapture() throws {
        guard let format = analyzerFormat, let input else {
            throw RecordingError.message("Recording is not prepared.")
        }
        let microphone = engine.inputNode
        let native = microphone.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: native.sampleRate,
                                       channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: mono, to: format) else {
            throw RecordingError.message("No usable microphone is connected.")
        }
        let notify: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor [weak self] in self?.report?(text) }
        }
        let pipeline = ConversionPipeline(source: mono, destination: format, converter: converter)
        let (chunks, audio) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.audio = audio
        feedTask = Task.detached(priority: .userInitiated) {
            var lost = 0.0
            for await chunk in chunks {
                let seconds = chunk.sampleRate > 0 ? Double(chunk.samples.count) / chunk.sampleRate : 0
                guard let buffer = pipeline.convert(chunk) else {
                    lost += seconds
                    if lost > tolerableLostSeconds {
                        notify("Audio conversion failed. Recording stopped to avoid an incomplete transcript.")
                        break
                    }
                    continue
                }
                if case .dropped = input.yield(AnalyzerInput(buffer: buffer)) {
                    lost += seconds
                    if lost > tolerableLostSeconds {
                        notify("Transcription could not keep up. Recording stopped; captured text is kept.")
                        break
                    }
                    continue
                }
                lost = 0
            }
        }
        let dropped = DroppedAudio()
        microphone.installTap(onBus: 0, bufferSize: 2_048, format: native) { @Sendable buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
            let rate = buffer.format.sampleRate
            if case .dropped = audio.yield(AudioChunk(samples: samples, sampleRate: rate, source: .you, timestamp: 0)) {
                if dropped.record(seconds: rate > 0 ? Double(samples.count) / rate : 0) {
                    notify("Audio processing could not keep up. Recording stopped; captured text is kept.")
                }
            } else {
                dropped.reset()
            }
        }
        hasTap = true
        engine.prepare()
        try engine.start()
    }

    private func stopCapture() async {
        if hasTap {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        audio?.finish()
        audio = nil
        await feedTask?.value
        feedTask = nil
    }

    func stop() async throws {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        await stopCapture()
        input?.finish()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            await resultsTask?.value
        } catch {
            await analyzer?.cancelAndFinishNow()
            resultsTask?.cancel()
            cleanup()
            throw error
        }
        cleanup()
    }

    private func cleanup() {
        analyzer = nil; input = nil; audio = nil; feedTask = nil; resultsTask = nil
        analyzerFormat = nil; report = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Owned by the single feed task that converts chunks; nothing else touches it.
private final class ConversionPipeline: @unchecked Sendable {
    private let source: AVAudioFormat
    private let destination: AVAudioFormat
    private let converter: AVAudioConverter

    init(source: AVAudioFormat, destination: AVAudioFormat, converter: AVAudioConverter) {
        self.source = source
        self.destination = destination
        self.converter = converter
    }

    func convert(_ chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(chunk.samples.count)),
              let data = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        chunk.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { data[0].update(from: base, count: samples.count) }
        }
        let capacity = AVAudioFrameCount(Double(chunk.samples.count) * destination.sampleRate / source.sampleRate) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}

/// Tracks continuously lost audio from the realtime tap callback, which has no actor.
private final class DroppedAudio: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 0.0
    private var reported = false

    /// Returns true once, when more than `tolerableLostSeconds` of audio has been lost in a row.
    func record(seconds duration: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        seconds += duration
        guard seconds > tolerableLostSeconds, !reported else { return false }
        reported = true
        return true
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        seconds = 0
    }
}

enum RecordingError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
