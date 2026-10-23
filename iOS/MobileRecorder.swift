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
    /// Optional copy of the transcribed audio for on-device speaker identification (issue #180).
    /// Set before `start`; `nil` (the default) means nothing is copied.
    func attachSpeakerAudio(_ buffer: SpeakerAudioBuffer?)
    /// Optional copy of the transcribed audio for spoken-language detection (issue #197). Set before `start`.
    func attachLanguageAudio(_ buffer: SpeakerAudioBuffer?)
    /// Restarts transcription in `locale` while capture keeps running (issue #197). Throws, changing
    /// nothing, when the new locale cannot be prepared. With `replay`, the new transcriber first hears
    /// that buffer's audio from the recording's start, so every line is transcribed again; without
    /// it, the new transcriber continues the timeline. `willReplace` runs once the old transcriber can
    /// deliver nothing more and before the new one delivers anything. Its arguments say whether the
    /// recording so far is being transcribed again, and the recording time at which the old one stopped.
    func switchLocale(to locale: Locale, replay: SpeakerAudioBuffer?,
                      willReplace: @escaping @MainActor (Bool, TimeInterval) -> Void) async throws
}

extension MobileRecording {
    func attachSpeakerAudio(_ buffer: SpeakerAudioBuffer?) {}
    func attachLanguageAudio(_ buffer: SpeakerAudioBuffer?) {}
    func switchLocale(to locale: Locale, replay: SpeakerAudioBuffer?,
                      willReplace: @escaping @MainActor (Bool, TimeInterval) -> Void) async throws {
        throw RecordingError.message("This recorder cannot change language while recording.")
    }
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
    /// Bumped when the transcriber is replaced, so a late result of the old one is never delivered.
    private var resultsGeneration = 0
    private var sink: AnalyzerSink?
    private var deliver: (@MainActor (TranscriptSegment) -> Void)?
    private var isSwitching = false
    private var isStopping = false
    private var hasTap = false
    private var analyzerFormat: AVAudioFormat?
    private var report: (@MainActor (String) -> Void)?
    private var configurationObserver: (any NSObjectProtocol)?
    /// The input format the installed tap was built for, and whether a rebuild is already running.
    /// One AirPods connection posts both a route change and an engine configuration change, and a
    /// restart on a new format can post another: without these, rebuilds chase each other.
    private var tapFormat: AVAudioFormat?
    private var isReconfiguring = false
    /// Receives exactly the audio the transcriber accepted, so diarized times and transcript times
    /// share one timeline. `nil` unless Identify speakers is on.
    private var speakerAudio: SpeakerAudioBuffer?
    private var speakerGeneration = 0
    /// The same audio for spoken-language detection; `nil` unless the language is Automatic.
    private var languageAudio: SpeakerAudioBuffer?
    private var languageGeneration = 0

    func attachSpeakerAudio(_ buffer: SpeakerAudioBuffer?) {
        speakerAudio = buffer
        speakerGeneration = buffer?.currentGeneration() ?? 0
    }

    func attachLanguageAudio(_ buffer: SpeakerAudioBuffer?) {
        languageAudio = buffer
        languageGeneration = buffer?.currentGeneration() ?? 0
    }

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        #if targetEnvironment(simulator)
        throw RecordingError.message(MobileSpeechModel.simulatorUnavailable)
        #else
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecordingError.message("Microphone access is off. Enable ListenToMe in Settings → Privacy & Security → Microphone.")
        }
        try Task.checkCancellation()
        let (transcriber, format) = try await MobileSpeechModel.prepare(locale: locale, volatileResults: true)
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
        deliver = onSegment
        sink = AnalyzerSink(input: input, destination: format, speakerAudio: speakerAudio,
                            speakerGeneration: speakerGeneration, languageAudio: languageAudio,
                            languageGeneration: languageGeneration)
        resultsTask = consumeResults(of: transcriber)
        try startCapture()
        observeConfigurationChanges()
        #endif
    }

    /// Delivers one transcriber's results until it is replaced or stopped.
    private func consumeResults(of transcriber: SpeechTranscriber) -> Task<Void, Never> {
        let generation = resultsGeneration
        return Task {
            do {
                for try await result in transcriber.results {
                    guard generation == resultsGeneration else { return }
                    let text = String(result.text.characters)
                    guard !result.isFinal || !text.isEmpty else { continue }
                    deliver?(TranscriptSegment(source: .you, text: text, isFinal: result.isFinal,
                                               start: result.range.start.seconds, end: result.range.end.seconds,
                                               speakerName: "Microphone"))
                }
                if generation == resultsGeneration, engine.isRunning {
                    report?("Transcription ended. Recording stopped; captured text is kept.")
                }
            } catch {
                if !Task.isCancelled, generation == resultsGeneration {
                    report?("Transcription stopped: \(error.localizedDescription)")
                }
            }
        }
    }

    func switchLocale(to locale: Locale, replay: SpeakerAudioBuffer?,
                      willReplace: @escaping @MainActor (Bool, TimeInterval) -> Void) async throws {
        guard let sink, input != nil, !isSwitching else { throw RecordingError.message("Recording is not running.") }
        isSwitching = true
        defer { isSwitching = false }
        let (transcriber, format) = try await MobileSpeechModel.prepare(locale: locale, volatileResults: true)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        // Replayed audio reaches the new analyzer much faster than real time; live audio queues behind it.
        let (inputs, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(1_024))
        try await analyzer.start(inputSequence: inputs)
        guard self.sink === sink, !isStopping, let previous = self.analyzer else {
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        }
        // From here to `resume` nothing awaits, so no result and no audio slips between the two transcribers.
        let cut = sink.hold()
        resultsGeneration &+= 1
        self.input?.finish()
        resultsTask?.cancel()
        self.analyzer = analyzer
        self.analyzerFormat = format
        self.input = input
        let replayed = replay.map {
            Self.replay($0, through: cut.languageSamples, into: input, format: format)
        } ?? false
        willReplace(replayed, cut.deliveredSeconds)
        resultsTask = consumeResults(of: transcriber)
        sink.resume(input: input, destination: format, continueAt: replayed ? nil : cut.deliveredSeconds)
        Task { await previous.cancelAndFinishNow() }
    }

    /// Feeds 16 kHz audio from the recording's start into a new analyzer, a few seconds per buffer.
    /// Returns false, feeding nothing, when that audio is gone or cannot be converted.
    static func replay(_ buffer: SpeakerAudioBuffer, through samples: Int,
                       into input: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) -> Bool {
        let audio = buffer.snapshot(fromSample: 0)
        guard !buffer.didTruncate, audio.startSample == 0, samples > 0, audio.samples.count >= samples,
              let pipeline = ConversionPipeline(sourceRate: Double(LanguageDetectionPolicy.sampleRate),
                                                destination: format) else { return false }
        let step = LanguageDetectionPolicy.sampleRate * 2
        var buffers: [AVAudioPCMBuffer] = []
        for start in stride(from: 0, to: samples, by: step) {
            guard let converted = pipeline.convert(Array(audio.samples[start..<min(samples, start + step)])) else {
                return false
            }
            buffers.append(converted)
        }
        for converted in buffers { input.yield(AnalyzerInput(buffer: converted)) }
        return true
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
        guard analyzerFormat != nil, hasTap || engine.isRunning, !isReconfiguring else { return }
        // The engine already matches the current input, so the tap is live and there is nothing to
        // rebuild. This is the common duplicate: a route change and a configuration change for the
        // same physical event, and the extra change a successful restart posts itself.
        if hasTap, engine.isRunning, let tapFormat,
           engine.inputNode.outputFormat(forBus: 0).isEqual(tapFormat) { return }
        isReconfiguring = true
        defer { isReconfiguring = false }
        await stopCapture()
        try startCapture()
    }

    /// Install the tap and the conversion pipeline for whatever input the engine currently has.
    /// Conversion runs on a detached task: a main-thread stall must never cost audio.
    private func startCapture() throws {
        guard analyzerFormat != nil, input != nil, let sink else {
            throw RecordingError.message("Recording is not prepared.")
        }
        let microphone = engine.inputNode
        let native = microphone.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0, sink.canConvert(sampleRate: native.sampleRate) else {
            throw RecordingError.message("No usable microphone is connected.")
        }
        let notify: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor [weak self] in self?.report?(text) }
        }
        let (chunks, audio) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.audio = audio
        feedTask = Task.detached(priority: .userInitiated) {
            var lost = 0.0
            for await chunk in chunks {
                // The sink copies a chunk for speakers and language only after the analyzer accepted it:
                // a dropped or unconvertible chunk is missing from all of them, so timelines never drift.
                let delivery = sink.deliver(chunk)
                if delivery == .accepted { lost = 0; continue }
                lost += chunk.sampleRate > 0 ? Double(chunk.samples.count) / chunk.sampleRate : 0
                guard lost > tolerableLostSeconds else { continue }
                notify(delivery == .dropped
                       ? "Transcription could not keep up. Recording stopped; captured text is kept."
                       : "Audio conversion failed. Recording stopped to avoid an incomplete transcript.")
                return
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
        tapFormat = native
        engine.prepare()
        try engine.start()
    }

    private func stopCapture() async {
        if hasTap {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
            tapFormat = nil
        }
        audio?.finish()
        audio = nil
        await feedTask?.value
        feedTask = nil
    }

    func stop() async throws {
        isStopping = true
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
        analyzerFormat = nil; report = nil; tapFormat = nil; speakerAudio = nil
        languageAudio = nil; sink = nil; deliver = nil; isStopping = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
