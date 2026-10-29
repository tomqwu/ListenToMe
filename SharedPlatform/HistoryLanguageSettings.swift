import SwiftUI
import ListenToMeCore

struct HistoryLanguageSettings: View {
    @State private var model = HistoryLanguageModel.shared

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                Text("Additional History languages").font(.headline)
                Text("Optional local search for German, Spanish, Japanese and Korean. " +
                     "Experimental: related results can miss conversations; exact-word search stays available.")
                    .font(.caption)
                Text("Downloads 1.13 GB from Hugging Face. Your conversations and searches stay on this device. " +
                     "This changes History search only; your summary provider stays the same.")
                    .font(.caption)
            }
            switch model.state {
            case .checking:
                ProgressView("Checking downloaded files…")
            case .downloading:
                ProgressView("Downloading search model…", value: model.progress)
                Button("Cancel download", role: .cancel) { model.cancel() }
                    .accessibilityIdentifier("historyModelCancel")
            case .removing:
                ProgressView("Removing search model…")
            case .ready:
                Toggle("Use additional search languages", isOn: Binding(
                    get: { model.enabled }, set: { model.setEnabled($0) }))
                    .accessibilityIdentifier("historyModelEnabled")
                Button("Remove downloaded model", role: .destructive) { model.remove() }
                    .accessibilityIdentifier("historyModelRemove")
            case .notInstalled, .failed:
                if case .failed(let message) = model.state { Text(message).font(.caption) }
                Button("Download and enable (1.13 GB)") { model.download() }
                    .accessibilityIdentifier("historyModelDownload")
            }
            Text("Long passages beyond the model’s limit use exact-word search. " +
                 "Downloading or removing the model does not delete conversations.")
                .font(.caption)
        }
        // Keep controls in separate native Form rows so enabling cannot activate Remove.
        .task { model.refreshIfNeeded() }
    }
}
