import Foundation

/// Cheap activity evidence for language checks, not a speech recognizer. Loud background noise can
/// qualify too; the language model's confidence and switching rules remain authoritative.
public enum LanguageAudioActivity {
    public static let frameSamples = 320 // 20 ms at 16 kHz
    public static let threshold: Double = 0.02

    /// Complete frames only. The caller retains a partial trailing frame for the next scan.
    /// Returns merged ranges on the recording's sample timeline, with no double counting of silence.
    public static func ranges(in samples: [Float], startSample: Int) -> [Range<TimeInterval>] {
        guard startSample >= 0, startSample <= Int.max - samples.count else { return [] }
        let frames = samples.count / frameSamples
        var result: [Range<TimeInterval>] = []
        for frame in 0..<frames {
            let lower = frame * frameSamples
            var energy: Double = 0
            var valid = true
            for sample in samples[lower..<(lower + frameSamples)] {
                guard sample.isFinite else { valid = false; break }
                let value = min(1, max(-1, Double(sample)))
                energy += value * value
            }
            guard valid, energy / Double(frameSamples) >= threshold * threshold else { continue }
            let start = Double(startSample + lower) / Double(LanguageDetectionPolicy.sampleRate)
            let end = Double(startSample + lower + frameSamples) / Double(LanguageDetectionPolicy.sampleRate)
            if let last = result.last, abs(last.upperBound - start) < 0.000_001 {
                result[result.count - 1] = last.lowerBound..<end
            } else {
                result.append(start..<end)
            }
        }
        return result
    }
}

extension LanguageTracker {
    /// Audio and recognizer ranges share one union, so overlapping evidence never inflates speech.
    public mutating func noteAudioActivity(_ ranges: [Range<TimeInterval>]) {
        for range in ranges where range.lowerBound >= 0 && range.upperBound > range.lowerBound {
            noteActivity(start: range.lowerBound, end: range.upperBound)
        }
    }
}
