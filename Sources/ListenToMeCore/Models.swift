import Foundation

/// Who produced the audio: the local user (microphone) or remote participants (system audio).
public enum SpeakerSource: String, Sendable, Codable, Equatable {
    case you
    case others
}

/// A buffer of mono PCM samples (normalized to -1...1) tagged with its source and capture time.
public struct AudioChunk: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let source: SpeakerSource
    public let timestamp: TimeInterval

    public init(samples: [Float], sampleRate: Double, source: SpeakerSource, timestamp: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.source = source
        self.timestamp = timestamp
    }
}

/// One unit of transcribed speech. Partial segments (`isFinal == false`) are replaced as more
/// audio arrives; finalized segments are appended to the conversation log.
public struct TranscriptSegment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: SpeakerSource
    public let text: String
    public let isFinal: Bool
    public let start: TimeInterval
    public let end: TimeInterval

    public init(id: UUID = UUID(), source: SpeakerSource, text: String,
                isFinal: Bool, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.source = source
        self.text = text
        self.isFinal = isFinal
        self.start = start
        self.end = end
    }
}
