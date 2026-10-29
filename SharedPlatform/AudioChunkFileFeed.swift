import AVFoundation
import Foundation
import Speech
import ListenToMeCore

/// The analyzer pulls one buffer at a time, so a three-hour recording is never held in memory.
struct ChunkInputs: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput
    let feed: ChunkFeed

    struct AsyncIterator: AsyncIteratorProtocol {
        let feed: ChunkFeed
        mutating func next() async -> AnalyzerInput? {
            guard let pcm = feed.nextPCM() else { return nil }
            return AnalyzerInput(buffer: pcm.buffer, bufferStartTime: pcm.bufferStartTime)
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(feed: feed) }
}

/// A decoded buffer for local waveform analysis. Raw Float32 consumers must not construct
/// AnalyzerInput: the physical Speech framework can trap on unsupported PCM representations.
struct ChunkPCM {
    let buffer: AVAudioPCMBuffer
    let bufferStartTime: CMTime?
}

/// Reads the chunks in order, about a second at a time, converted to the analyzer's format. Each
/// chunk's first buffer carries the chunk's start on the recording's timeline, so results come back
/// in recording time even across a gap. The analyzer's time never steps backward: a chunk that
/// claims to start inside audio already fed (its predecessor ran long) starts where that audio
/// ended. A read failure ends the input and is kept in `failure`.
final class ChunkFeed: @unchecked Sendable {
    private let lock = NSLock()
    private let chunks: [LocalAudioChunk]
    private let format: AVAudioFormat
    private var position = 0
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var startsChunk = false
    /// Recording time at the end of the audio fed so far.
    private var fedThrough: TimeInterval = 0
    private var stopped = false
    private var storedFailure: (any Error)?

    init(chunks: [LocalAudioChunk], format: AVAudioFormat) {
        self.chunks = chunks
        self.format = format
    }

    var isStopped: Bool { lock.withLock { stopped } }
    var failure: (any Error)? { lock.withLock { storedFailure } }

    func stop(failing error: (any Error)?) {
        lock.withLock {
            stopped = true
            if storedFailure == nil { storedFailure = error }
        }
    }

    /// Raw audio analysis uses this path without entering the Speech framework.
    func nextPCM() -> ChunkPCM? {
        lock.withLock {
            do {
                while !stopped, position < chunks.count {
                    if let input = try read() { return input }
                }
            } catch {
                stopped = true
                storedFailure = storedFailure ?? error
            }
            return nil
        }
    }

    /// The next converted buffer of the current chunk, or `nil` after moving on to the next chunk.
    private func read() throws -> ChunkPCM? {
        let chunk = chunks[position]
        if file == nil {
            let opened = try AVAudioFile(forReading: chunk.url)
            file = opened
            let source = opened.processingFormat
            converter = source == format ? nil : AVAudioConverter(from: source, to: format)
            if source != format, converter == nil {
                throw LocalAudioFileError.message("Saved audio is in a format this iPhone cannot convert.")
            }
            startsChunk = true
        }
        guard let file else { return nil }
        let output: AVAudioPCMBuffer
        var finished = false
        if file.framePosition >= file.length {
            guard converter != nil else { finishChunk(); return nil }
            // File EOF is not converter EOF: retained samples must be drained before
            // releasing this converter or opening the next chunk.
            (output, finished) = try convert(nil)
            if !finished, output.frameLength == 0 {
                throw LocalAudioFileError.message("Saved audio conversion stopped making progress at EOF.")
            }
        } else {
            let source = file.processingFormat
            let frames = AVAudioFrameCount(max(1, source.sampleRate.rounded()))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames) else {
                throw LocalAudioFileError.message("Could not read Saved audio.")
            }
            try file.read(into: buffer, frameCount: frames)
            guard buffer.frameLength > 0 else {
                throw LocalAudioFileError.message("Saved audio ended before all declared frames could be read.")
            }
            if converter != nil {
                (output, finished) = try convert(buffer)
                if finished {
                    throw LocalAudioFileError.message("Saved audio conversion ended before source EOF.")
                }
            } else {
                output = buffer
            }
        }
        if finished { finishChunk() }
        guard output.frameLength > 0 else { return nil }
        var start: CMTime?
        if startsChunk {
            fedThrough = max(chunk.startOffset, fedThrough)
            start = CMTime(seconds: fedThrough, preferredTimescale: 48_000)
            startsChunk = false
        }
        fedThrough += Double(output.frameLength) / format.sampleRate
        return ChunkPCM(buffer: output, bufferStartTime: start)
    }

    private func finishChunk() {
        file = nil
        converter = nil
        position += 1
    }

    /// A nil input supplies permanent EOF, unlike a temporarily exhausted input buffer.
    private func convert(_ buffer: AVAudioPCMBuffer?) throws -> (AVAudioPCMBuffer, Bool) {
        guard let converter else {
            throw LocalAudioFileError.message("Saved audio converter is unavailable.")
        }
        let outputFrames = buffer.map { Double($0.frameLength) * format.sampleRate / $0.format.sampleRate }
            ?? max(1, format.sampleRate.rounded())
        let capacity = AVAudioFrameCount(outputFrames.rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw LocalAudioFileError.message("Could not convert Saved audio.")
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            guard let buffer else { status.pointee = .endOfStream; return nil }
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        switch status {
        case .error:
            throw LocalAudioFileError.message("Could not convert Saved audio.")
        case .endOfStream:
            return (output, true)
        case .haveData, .inputRanDry:
            return (output, false)
        @unknown default:
            throw LocalAudioFileError.message("Saved audio conversion returned an unsupported state.")
        }
    }
}
