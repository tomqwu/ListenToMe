import CoreML
import WhisperKit

/// The displayed policy is the exact options value passed to WhisperKit, not a hardware-usage claim.
enum WhisperComputePolicy {
    static let options = ModelComputeOptions()

    static func label(_ units: MLComputeUnits) -> String {
        switch units {
        case .cpuOnly: return "CPU"
        case .cpuAndGPU: return "CPU + GPU"
        case .cpuAndNeuralEngine: return "CPU + Neural Engine"
        case .all: return "CPU + GPU + Neural Engine"
        @unknown default: return "Unknown"
        }
    }
}

