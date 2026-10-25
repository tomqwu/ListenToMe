import SwiftUI
import CoreML
import WhisperKit

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

    var runtime: String {
        if isPreparing { return "Preparing · Not exposed" }
        return isRunning ? "Not exposed" : "Not running"
    }
}
