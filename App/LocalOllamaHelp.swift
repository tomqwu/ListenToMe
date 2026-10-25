import SwiftUI
import ListenToMeCore

struct LocalOllamaHelp: View {
    let readiness: LocalOllamaReadiness
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if readiness.status == .unavailable {
                    Link("Install Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                }
                if readiness.needsModel {
                    Button("Copy model download command") { Clipboard.copy(LocalOllamaReadiness.pullCommand) }
                }
                Button("Retry local check", action: retry)
            }
            if readiness.needsModel {
                Text("Run in Terminal: \(LocalOllamaReadiness.pullCommand). This downloads a model; it does not send conversation text.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
