import AVFoundation
import Foundation
import ListenToMeCore

/// Pull-based file windows: at most 60 seconds of mono PCM plus one input buffer, off the UI actor.
/// Unlike a live trailing buffer, every window is analyzed before advancing, even in a long file.
actor WatchSpeakerAudio {
    struct Window: Sendable {
        let samples: [Float]
        let start: TimeInterval
    }

    private let feed: ChunkFeed
    private var samples: [Float] = []
    private var start: TimeInterval = 0
    private var clock: TimeInterval = 0
    private var pending: Window?
    private var fresh = false
    private var ended = false
    private static let rate = 16_000
    private static let capacity = rate * 60
    private static let overlap = rate * 10

    init(chunks: [WatchAudioChunk]) {
        feed = ChunkFeed(chunks: chunks, format: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!)
    }

    func next() throws -> Window? {
        try Task.checkCancellation()
        while !ended {
            try Task.checkCancellation()
            let input: Window
            if let held = pending {
                input = held
                pending = nil
            } else if let value = feed.nextPCM() {
                try Task.checkCancellation()
                let buffer = value.buffer
                guard let channel = buffer.floatChannelData?[0] else { continue }
                let time = value.bufferStartTime?.seconds ?? clock
                input = Window(samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
                               start: time)
                clock = time + Double(input.samples.count) / Double(Self.rate)
            } else {
                ended = true
                if let error = feed.failure { throw error }
                return flush(keepingOverlap: false)
            }
            let expected = start + Double(samples.count) / Double(Self.rate)
            if !samples.isEmpty, abs(input.start - expected) > 0.001 {
                pending = input
                if let result = flush(keepingOverlap: false) { return result }
                continue
            }
            if samples.isEmpty { start = input.start }
            let take = min(input.samples.count, Self.capacity - samples.count)
            samples.append(contentsOf: input.samples.prefix(take))
            if take < input.samples.count {
                pending = Window(samples: Array(input.samples.dropFirst(take)),
                                 start: input.start + Double(take) / Double(Self.rate))
            }
            fresh = true
            if samples.count >= Self.capacity { return flush(keepingOverlap: true) }
        }
        return nil
    }

    private func flush(keepingOverlap: Bool) -> Window? {
        let result = fresh && samples.count >= SpeakerAnalysisPolicy.minimumSamples
            ? Window(samples: samples, start: start) : nil
        if keepingOverlap {
            let removed = max(0, samples.count - Self.overlap)
            samples = Array(samples.suffix(Self.overlap))
            start += Double(removed) / Double(Self.rate)
        } else {
            samples = []
        }
        fresh = false
        return result
    }
}
