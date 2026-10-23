import AVFoundation
import Speech
import ListenToMeCore

/// Where captured microphone audio goes: converted into the current analyzer's input, and copied into
/// the speaker (#180) and language (#197) buffers only once the analyzer accepted it, so all three
/// share one timeline. The analyzer can be replaced while capture runs (a language switch): `hold`
/// parks new audio, `resume` points the sink at the new analyzer and sends what was parked, so no
/// microphone audio is lost and the copies stay continuous.
///
/// Used by the single feed task and, for `hold`/`resume`, the main actor; everything runs under `lock`.
final class AnalyzerSink: @unchecked Sendable {
    enum Delivery { case accepted, dropped, unconvertible }

    /// What `hold` saw: the language buffer's sample count and the seconds the old analyzer received.
    struct Cut {
        let languageSamples: Int
        let deliveredSeconds: TimeInterval
    }

    private let lock = NSLock()
    private var input: AsyncStream<AnalyzerInput>.Continuation
    private var destination: AVAudioFormat
    private var pipeline: ConversionPipeline?
    private var held: [AudioChunk]?
    private var deliveredSeconds: TimeInterval = 0
    /// Start time for the next buffer sent, when the new analyzer continues the timeline without a replay.
    private var nextStart: CMTime?
    private let speakerAudio: SpeakerAudioBuffer?
    private let speakerGeneration: Int
    private let languageAudio: SpeakerAudioBuffer?
    private let languageGeneration: Int

    init(input: AsyncStream<AnalyzerInput>.Continuation, destination: AVAudioFormat,
         speakerAudio: SpeakerAudioBuffer?, speakerGeneration: Int,
         languageAudio: SpeakerAudioBuffer?, languageGeneration: Int) {
        self.input = input
        self.destination = destination
        self.speakerAudio = speakerAudio
        self.speakerGeneration = speakerGeneration
        self.languageAudio = languageAudio
        self.languageGeneration = languageGeneration
    }

    func deliver(_ chunk: AudioChunk) -> Delivery {
        lock.withLock {
            if held != nil {
                held?.append(chunk)
                copy(chunk)
                return .accepted
            }
            let delivery = send(chunk)
            if delivery == .accepted { copy(chunk) }
            return delivery
        }
    }

    /// Parks new audio until `resume`. The returned cut says how much audio the current analyzer had.
    func hold() -> Cut {
        lock.withLock {
            if held == nil { held = [] }
            return Cut(languageSamples: languageAudio?.sampleCount ?? 0, deliveredSeconds: deliveredSeconds)
        }
    }

    /// Sends later audio to `input`, in `destination`'s format, starting with what `hold` parked.
    /// `continueAt` stamps the first buffer, so a new analyzer that heard no replay keeps the timeline.
    func resume(input: AsyncStream<AnalyzerInput>.Continuation, destination: AVAudioFormat, continueAt: TimeInterval?) {
        lock.withLock {
            self.input = input
            if !self.destination.isEqual(destination) { pipeline = nil }
            self.destination = destination
            nextStart = continueAt.map { CMTime(seconds: $0, preferredTimescale: 48_000) }
            let parked = held ?? []
            held = nil
            for chunk in parked { _ = send(chunk) }
        }
    }

    /// Whether audio at `sampleRate` can be converted for the current analyzer.
    func canConvert(sampleRate: Double) -> Bool {
        lock.withLock { pipeline(for: sampleRate) != nil }
    }

    /// PRECONDITION: `lock` is held.
    private func send(_ chunk: AudioChunk) -> Delivery {
        guard let buffer = pipeline(for: chunk.sampleRate)?.convert(chunk.samples) else { return .unconvertible }
        let start = nextStart
        if case .dropped = input.yield(AnalyzerInput(buffer: buffer, bufferStartTime: start)) { return .dropped }
        nextStart = nil
        deliveredSeconds += chunk.sampleRate > 0 ? Double(chunk.samples.count) / chunk.sampleRate : 0
        return .accepted
    }

    /// PRECONDITION: `lock` is held.
    private func copy(_ chunk: AudioChunk) {
        speakerAudio?.append(samples: chunk.samples, sampleRate: chunk.sampleRate, timestamp: 0,
                             generation: speakerGeneration)
        languageAudio?.append(samples: chunk.samples, sampleRate: chunk.sampleRate, timestamp: 0,
                              generation: languageGeneration)
    }

    /// PRECONDITION: `lock` is held. Rebuilt when the microphone's rate or the analyzer's format changes.
    private func pipeline(for sampleRate: Double) -> ConversionPipeline? {
        if let pipeline, pipeline.sourceRate == sampleRate { return pipeline }
        pipeline = ConversionPipeline(sourceRate: sampleRate, destination: destination)
        return pipeline
    }
}

/// Converts mono Float32 audio at one rate into an analyzer's format.
final class ConversionPipeline: @unchecked Sendable {
    let sourceRate: Double
    private let source: AVAudioFormat
    private let destination: AVAudioFormat
    private let converter: AVAudioConverter

    init?(sourceRate: Double, destination: AVAudioFormat) {
        guard sourceRate > 0,
              let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: destination) else { return nil }
        self.sourceRate = sourceRate
        self.source = source
        self.destination = destination
        self.converter = converter
    }

    func convert(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { values in
            if let base = values.baseAddress { data[0].update(from: base, count: values.count) }
        }
        let capacity = AVAudioFrameCount(Double(samples.count) * destination.sampleRate / source.sampleRate) + 1_024
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
