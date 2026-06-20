import Foundation

/// Root-mean-square energy of a PCM frame. 0 for empty input.
public func rms(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
    return (sumSquares / Float(samples.count)).squareRoot()
}

/// Detects utterance boundaries from a stream of per-frame RMS values.
/// `process` returns `true` exactly once, on the frame where trailing silence
/// after speech first exceeds `silenceDuration`.
public struct VADSegmenter {
    public let speechThreshold: Float
    public let silenceDuration: TimeInterval

    private var inSpeech = false
    private var lastSpeechTime: TimeInterval = 0

    public init(speechThreshold: Float = 0.02, silenceDuration: TimeInterval = 0.8) {
        self.speechThreshold = speechThreshold
        self.silenceDuration = silenceDuration
    }

    public mutating func process(rms value: Float, at time: TimeInterval) -> Bool {
        if value >= speechThreshold {
            inSpeech = true
            lastSpeechTime = time
            return false
        }
        if inSpeech && (time - lastSpeechTime) >= silenceDuration {
            inSpeech = false
            return true
        }
        return false
    }
}
