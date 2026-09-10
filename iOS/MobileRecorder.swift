import AVFoundation
import Speech
import ListenToMeCore

/// Foreground microphone capture. Model preparation completes before the audio tap starts.
@MainActor
final class MobileRecorder {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var audio: AsyncStream<AudioChunk>.Continuation?
    private var feedTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var hasTap = false

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
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
        let microphone = engine.inputNode
        let native = microphone.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: native.sampleRate,
                                       channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: mono, to: format) else {
            throw RecordingError.message("No usable microphone is connected.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
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
        let (chunks, audio) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.audio = audio
        feedTask = Task {
            for await chunk in chunks {
                guard let buffer = Self.convert(chunk, from: mono, to: format, using: converter) else {
                    onFailure("Audio conversion failed. Recording stopped to avoid an incomplete transcript.")
                    break
                }
                if case .dropped = input.yield(AnalyzerInput(buffer: buffer)) {
                    onFailure("Transcription could not keep up. Recording stopped; captured text is kept.")
                    break
                }
            }
            input.finish()
        }
        microphone.installTap(onBus: 0, bufferSize: 2_048, format: native) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
            if case .dropped = audio.yield(AudioChunk(samples: samples, sampleRate: buffer.format.sampleRate,
                                                     source: .you, timestamp: 0)) {
                Task { @MainActor in onFailure("Audio processing could not keep up. Recording stopped; captured text is kept.") }
            }
        }
        hasTap = true
        engine.prepare()
        try engine.start()
    }

    func stop() async throws {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        audio?.finish()
        await feedTask?.value
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func convert(_ chunk: AudioChunk, from source: AVAudioFormat,
                                to destination: AVAudioFormat, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
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

enum RecordingError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
