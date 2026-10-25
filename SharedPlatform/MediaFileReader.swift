import AVFoundation
import Foundation
import ListenToMeCore
import UniformTypeIdentifiers

/// Audio files use the existing paced reader; movie containers decode their first audio track only.
final class MediaFileChunkProducer: Sendable {
    private let audio: AudioFileChunkProducer?
    private let movie: MovieAudioChunkProducer?
    private init(audio: AudioFileChunkProducer? = nil, movie: MovieAudioChunkProducer? = nil) {
        self.audio = audio; self.movie = movie
    }
    static func open(url: URL, source: SpeakerSource) async throws -> MediaFileChunkProducer {
        try Task.checkCancellation()
        let isMovie = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
        if !isMovie, let audio = AudioFileChunkProducer(url: url, source: source) { return .init(audio: audio) }
        return try await .init(movie: MovieAudioChunkProducer.open(url: url, source: source))
    }
    func next() async throws -> AudioChunk? {
        try Task.checkCancellation()
        let chunk: AudioChunk?
        if let audio { chunk = try await audio.next() }
        else { chunk = try await movie?.next() }
        // AVAssetReader forbids concurrent cancelReading/copyNextSampleBuffer. Finish one queued
        // buffer safely, then reject it if cancellation arrived while that read was in flight.
        try Task.checkCancellation()
        return chunk
    }
    func progress() async -> Double {
        if let audio { return await audio.progress() }
        return await movie?.progress() ?? 0
    }
}

/// AVAssetReader and its output are confined to one serial queue after construction.
private final class MovieAudioChunkProducer: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let source: SpeakerSource
    private let duration: Double
    private let queue = DispatchQueue(label: "com.tomwu.ListenToMe.movie-audio-reader")
    private var fraction = 0.0
    private var ended = false

    private init(reader: AVAssetReader, output: AVAssetReaderAudioMixOutput, source: SpeakerSource, duration: Double) {
        self.reader = reader; self.output = output; self.source = source; self.duration = duration
    }
    deinit { reader.cancelReading() }

    static func open(url: URL, source: SpeakerSource) async throws -> MovieAudioChunkProducer {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw QuickSummaryError.message("This recording has no audio track to transcribe.")
        }
        let duration = try await asset.load(.duration).seconds
        try Task.checkCancellation()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw CocoaError(.fileReadUnsupportedScheme) }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return MovieAudioChunkProducer(reader: reader, output: output, source: source, duration: duration)
    }
    func next() async throws -> AudioChunk? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.read()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func progress() async -> Double {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.fraction) }
        }
    }
    private func read() throws -> AudioChunk? {
        if ended { return nil }
        guard let sample = output.copyNextSampleBuffer() else {
            guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
            ended = true; fraction = 1
            return nil
        }
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var settings = basic
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0, let format = AVAudioFormat(streamDescription: &settings),
              format.channelCount == 1, format.commonFormat == .pcmFormatFloat32,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        buffer.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count),
                                                          into: buffer.mutableAudioBufferList) == noErr,
              let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard timestamp.isFinite, format.sampleRate > 0 else { throw CocoaError(.fileReadCorruptFile) }
        if duration.isFinite, duration > 0 {
            fraction = min(1, max(fraction, (timestamp + Double(count) / format.sampleRate) / duration))
        }
        return AudioChunk(samples: Array(UnsafeBufferPointer(start: channel, count: count)),
                          sampleRate: format.sampleRate, source: source, timestamp: max(0, timestamp))
    }
}
