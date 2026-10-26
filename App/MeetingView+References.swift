import SwiftUI
import AppKit
import ListenToMeCore

extension MeetingView {
    func referenceFilesRow(session: MeetingSession) -> some View {
        HStack(spacing: 8) {
            Button { addReferenceFiles(session: session) } label: {
                Label("Add files / folders", systemImage: "paperclip")
            }
            .help("Attach local files or folders as reference context for Quick & Deep answers")
            if !referencePaths.isEmpty {
                Text(referenceSummary)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !referenceSkipped.isEmpty {
                    Label(referenceSkippedSummary, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).lineLimit(1)
                        .help(referenceSkippedDetail)
                }
                Button("Clear") { clearReferences(session: session) }
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    var referenceSummary: String {
        let names = referencePaths.map { $0.lastPathComponent }
        let shown = names.prefix(2).joined(separator: ", ")
        return referencePaths.count > 2 ? "\(shown) +\(referencePaths.count - 2) more" : shown
    }

    /// One-line "not included" status so a file the model never saw is never invisible.
    var referenceSkippedSummary: String {
        guard let first = referenceSkipped.first else { return "" }
        return referenceSkipped.count == 1
            ? "Not included: \(first.name) (\(first.reason))"
            : "\(referenceSkipped.count) files not included"
    }

    var referenceSkippedDetail: String {
        "Not included in reference context:\n"
            + referenceSkipped.map { "• \($0.name) — \($0.reason)" }.joined(separator: "\n")
    }

    func addReferenceFiles(session: MeetingSession) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders to use as reference context"
        guard panel.runModal() == .OK else { return }
        // De-duplicate by standardized path while preserving order.
        var seen = Set(referencePaths.map { $0.standardizedFileURL.path })
        for url in panel.urls where seen.insert(url.standardizedFileURL.path).inserted {
            referencePaths.append(url)
        }
        persistReferencePaths()
        loadReferences(into: session)
    }

    func clearReferences(session: MeetingSession) {
        referencePaths = []
        referenceSkipped = []
        referenceContext.cancel()
        persistReferencePaths()
        session.referenceContext = nil
    }

    private func persistReferencePaths() {
        UserDefaults.standard.set(referencePaths.map(\.path), forKey: "referencePaths")
    }

    /// Reads the attached files/folders off the main actor and updates the session's grounding.
    func loadReferences(into session: MeetingSession) {
        referenceContext.load(referencePaths, maxChars: ProviderSettings.referenceBudget) { update in
            referenceSkipped = update.skipped
            session.referenceContext = update.context
        }
    }
}
