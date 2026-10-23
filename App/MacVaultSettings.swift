import AppKit
import SwiftUI
import ListenToMeCore

/// Settings → Save to folder (issue #53). Off by default; applies immediately, like choosing a file.
struct MacVaultSettings: View {
    @Bindable var vault = MarkdownVaultSync.shared

    var body: some View {
        Toggle("Save each conversation to a folder as Markdown", isOn: Binding(get: { vault.enabled }, set: { on in
            vault.setEnabled(on)
            if on && !vault.hasFolder { chooseFolder() }
        }))
        if vault.enabled {
            HStack {
                Text(vault.folderName.map { "Folder: \($0)" } ?? "No folder chosen")
                Spacer()
                Button(vault.hasFolder ? "Change Folder…" : "Choose Folder…") { chooseFolder() }
                if vault.isFailing || !vault.unsavedIDs.isEmpty {
                    // The conversation being recorded is skipped (`activeRecordingID`).
                    Button("Retry") {
                        vault.retry(history: SessionStore().all(),
                                    language: ProviderSettings.transcriptionLocale().identifier)
                    }.disabled(!vault.hasFolder)
                }
            }
            Text(vault.statusText).font(.caption).foregroundStyle(vault.isFailing ? .orange : .secondary)
        }
        Text("Writes one note per conversation (front matter, summary, notes, timestamped transcript) when you stop, " +
             "then updates it as summaries change. Works with an Obsidian vault. Follows \u{201C}Save sessions " +
             "locally\u{201D}; deleting a conversation here does not delete its note.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder or Obsidian vault for ListenToMe notes."
        if panel.runModal() == .OK, let url = panel.url { vault.chooseFolder(url) }
    }
}

extension MeetingView {
    /// Save to folder notes left unwritten when the app last quit are written at launch, like iOS
    /// does on its next save. Only reads History when something is waiting.
    func retryVaultNotesAtLaunch() {
        let vault = MarkdownVaultSync.shared
        guard vault.enabled, !vault.unsavedIDs.isEmpty else { return }
        vault.retry(history: sessionStore.all(), language: ProviderSettings.transcriptionLocale().identifier)
    }
}
