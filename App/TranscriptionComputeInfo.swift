import SwiftUI
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

struct TranscriptionComputeInfo: View {
    let engine: String
    let isRunning: Bool
    let isPreparing: Bool

    var body: some View {
        DisclosureGroup("Compute details") {
            VStack(alignment: .leading, spacing: 5) {
                if engine == "whisperKit" {
                    Text("Configured compute units")
                    Text("Audio features: \(WhisperComputePolicy.label(WhisperComputePolicy.options.melCompute))")
                    Text("Encoder: \(WhisperComputePolicy.label(WhisperComputePolicy.options.audioEncoderCompute))")
                    Text("Decoder: \(WhisperComputePolicy.label(WhisperComputePolicy.options.textDecoderCompute))")
                    Text("Prefill: \(WhisperComputePolicy.label(WhisperComputePolicy.options.prefillCompute))")
                } else {
                    Text("Configured compute: managed by Apple Speech")
                }
                Divider()
                Text("Runtime accelerator: \(runtime)")
                Text("The speech framework does not expose per-request hardware use. "
                     + "Configured units are allowed devices, not proof that GPU or Neural Engine is active.")
            }
            .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .font(.caption)
        .accessibilityIdentifier("transcriptionComputeDetails")
    }

    private var runtime: String {
        if isPreparing { return "Preparing · Not exposed" }
        return isRunning ? "Not exposed" : "Not running"
    }
}
