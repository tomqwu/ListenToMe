import AVFoundation
import CoreMedia
import Speech
import ListenToMeCore
import Foundation

/// One native conversion/input boundary per analyzer pipeline. Capture timestamps stay on chunks.
final class MacAnalyzerInputAdapter {
    enum InputError: LocalizedError {
        case invalidAudio, invalidTimestamp, clockDiscontinuity, conversionFailed, queueFull

        var errorDescription: String? {
            switch self {
            case .invalidAudio, .conversionFailed: "Audio format could not be prepared. Stop and restart."
            case .invalidTimestamp, .clockDiscontinuity: "Audio timing changed unexpectedly. Stop and restart."
            case .queueFull: "Transcription input could not keep up. Stop and restart."
            }
        }
    }

    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var rawEnd: TimeInterval?
    private var previousInputDuration: TimeInterval?
    private var convertedEnd: CMTime?
    private var stopped = false
    /// Resource-free checkpoint permits deterministic cancellation at the native conversion boundary.
    private let conversionCheckpoint: @Sendable () -> Void

    init(format: AVAudioFormat, conversionCheckpoint: @escaping @Sendable () -> Void = {}) {
        self.format = format
        self.conversionCheckpoint = conversionCheckpoint
    }

    /// The raw boundary detects local clock discontinuities. The exact converted boundary keeps
    /// samples contiguous despite resampling and long-running hardware/host-clock drift. Genuine
    /// raw gaps are carried onto that sample timeline; original chunks and saved audio are untouched.
    @discardableResult
    func send(_ chunk: AudioChunk, to continuation: AsyncStream<AnalyzerInput>.Continuation) throws -> Bool {
        guard !stopped, !Task.isCancelled, !chunk.samples.isEmpty else { return false }
        guard chunk.sampleRate.isFinite, chunk.sampleRate > 0, chunk.sampleRate <= Double(Int32.max),
              format.sampleRate.isFinite, format.sampleRate > 0,
              format.sampleRate <= Double(Int32.max), format.sampleRate.rounded() == format.sampleRate,
              chunk.samples.count < Int(UInt32.max) else { throw InputError.invalidAudio }
        if #available(macOS 27.0, *), format.commonFormat != .pcmFormatInt16 {
            // This runtime's AnalyzerInput constructor traps for other PCM representations.
            // Earlier runtimes retain their negotiated format; do not narrow their support.
            throw InputError.invalidAudio
        }
        let inputDuration = Double(chunk.samples.count) / chunk.sampleRate
        guard inputDuration.isFinite, inputDuration > 0 else { throw InputError.invalidAudio }
        guard chunk.timestamp.isFinite, chunk.timestamp >= 0,
              (chunk.timestamp + inputDuration).isFinite else { throw InputError.invalidTimestamp }
        // Up to 1 ms of local host-clock jitter, capped at a quarter of the shorter adjacent
        // source buffer so an exact duplicate can never masquerade as small jitter.
        let tolerance = min(0.001, min(previousInputDuration ?? inputDuration, inputDuration) / 4)
        let rawGap = rawEnd.map { chunk.timestamp - $0 } ?? 0
        guard rawGap >= -tolerance else { throw InputError.clockDiscontinuity }
        let gap = rawGap > tolerance ? rawGap : 0
        let start = convertedEnd.map {
            CMTimeAdd($0, CMTime(seconds: gap, preferredTimescale: 1_000_000))
        } ?? CMTime(seconds: chunk.timestamp, preferredTimescale: 1_000_000)
        guard start.isNumeric else { throw InputError.invalidTimestamp }
        guard let buffer = convert(chunk) else {
            stop()
            throw InputError.conversionFailed
        }
        conversionCheckpoint()
        guard !stopped, !Task.isCancelled else {
            stop() // Conversion consumed input; do not reuse advanced state with old timing boundaries.
            return false
        }
        if buffer.frameLength == 0 {
            // Resampling may consume a valid sub-frame input without producing output yet.
            // Retain its first anchor and raw boundary while the converter accumulates samples.
            rawEnd = chunk.timestamp + inputDuration
            previousInputDuration = inputDuration
            convertedEnd = start
            return false
        }
        let end = CMTimeAdd(start, CMTime(value: CMTimeValue(buffer.frameLength),
                                        timescale: CMTimeScale(format.sampleRate)))
        guard end.isNumeric, CMTimeCompare(end, start) > 0 else { stop(); throw InputError.invalidAudio }
        switch continuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: start)) {
        case .enqueued:
            rawEnd = chunk.timestamp + inputDuration
            previousInputDuration = inputDuration
            convertedEnd = end
            return true
        case .dropped:
            stop()
            throw InputError.queueFull
        case .terminated:
            stop()
            return false
        @unknown default:
            stop()
            return false
        }
    }

    func stop() { stopped = true; converter = nil }

    private func convert(_ chunk: AudioChunk) -> AVAudioPCMBuffer? {
        guard !chunk.samples.isEmpty, chunk.sampleRate.isFinite, chunk.sampleRate > 0,
              let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: chunk.sampleRate,
                                         channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: source,
                                           frameCapacity: AVAudioFrameCount(chunk.samples.count)) else { return nil }
        input.frameLength = input.frameCapacity
        chunk.samples.withUnsafeBufferPointer { values in
            if let base = values.baseAddress { input.floatChannelData?[0].update(from: base, count: values.count) }
        }
        if source == format { return input }
        if converter?.inputFormat != source {
            converter = AVAudioConverter(from: source, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / source.sampleRate
        let requestedCapacity = (Double(chunk.samples.count) * ratio).rounded(.up) + 1_024
        guard requestedCapacity.isFinite, requestedCapacity > 0,
              requestedCapacity <= Double(UInt32.max) else { return nil }
        let capacity = AVAudioFrameCount(requestedCapacity)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true; status.pointee = .haveData
            return input
        }
        return error == nil ? output : nil
    }
}
