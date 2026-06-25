import Foundation
import AVFoundation
import ListenToMeCore

/// Pull-based reader for an audio file (any format AVAudioFile supports — m4a, mp3, wav, aiff,
/// caf, …). Each `next()` reads and converts one block to a mono Float32 `AudioChunk`, so only a
/// single block is held in memory at a time — the consumer's `feed` rate paces the disk reads
/// (no unbounded buffering for long files). Reads run on a private serial queue, off the main actor.
final class AudioFileChunkProducer: @unchecked Sendable {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let sampleRate: Double
    private let source: SpeakerSource
    private var framePosition: AVAudioFramePosition = 0
    private let queue = DispatchQueue(label: "com.tomwu.ListenToMe.audio-file-reader")
    private static let blockSize: AVAudioFrameCount = 8192

    init?(url: URL, source: SpeakerSource) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        guard format.sampleRate > 0 else { return nil }
        self.file = file
        self.format = format
        self.sampleRate = format.sampleRate
        self.source = source
    }

    /// The next chunk, or nil at end of file. Reads happen on a serial background queue.
    func next() async -> AudioChunk? {
        await withCheckedContinuation { (continuation: CheckedContinuation<AudioChunk?, Never>) in
            queue.async { [weak self] in
                continuation.resume(returning: self?.readBlock())
            }
        }
    }

    /// Reads forward until it yields a convertible chunk or hits EOF (nil). Serial-queue only.
    private func readBlock() -> AudioChunk? {
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.blockSize)
            else { return nil }
            do { try file.read(into: buffer, frameCount: Self.blockSize) } catch { return nil }
            if buffer.frameLength == 0 { return nil }   // end of file
            let timestamp = Double(framePosition) / sampleRate
            framePosition += AVAudioFramePosition(buffer.frameLength)
            if let chunk = Self.chunk(from: buffer, source: source, timestamp: timestamp) {
                return chunk
            }
            // conversion produced nothing for this block; advance to the next
        }
    }

    private static func chunk(from buffer: AVAudioPCMBuffer, source: SpeakerSource,
                              timestamp: TimeInterval) -> AudioChunk? {
        guard let mono = toMonoFloat(buffer), let channel = mono.floatChannelData?[0] else { return nil }
        let count = Int(mono.frameLength)
        guard count > 0 else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        return AudioChunk(samples: samples, sampleRate: mono.format.sampleRate,
                          source: source, timestamp: timestamp)
    }

    /// Converts any PCM buffer to non-interleaved mono Float32 at the same sample rate (downmixing
    /// stereo). Returns the input unchanged when already in that format.
    private static func toMonoFloat(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let inFormat = input.format
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: inFormat.sampleRate,
                                            channels: 1, interleaved: false) else { return nil }
        if inFormat == outFormat { return input }
        guard input.frameLength > 0,
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: input.frameLength) else { return nil }
        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: output, error: &convError) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true; outStatus.pointee = .haveData; return input
        }
        if status == .error || convError != nil { return nil }
        return output
    }
}
