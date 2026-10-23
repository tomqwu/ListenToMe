import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

/// Settings → Save to folder (issue #53): off by default. The folder comes from the Files picker,
/// so it can be On My iPhone, iCloud Drive or an Obsidian vault.
struct MobileVaultSettings: View {
    let session: MobileSession
    @Bindable var vault: MarkdownVaultSync
    @State private var picking = false

    init(session: MobileSession, vault: MarkdownVaultSync = MobileSession.markdownVault) {
        self.session = session
        self.vault = vault
    }

    var body: some View {
        Section {
            Toggle("Save to folder", isOn: Binding(get: { vault.enabled }, set: { on in
                vault.setEnabled(on)
                if on && !vault.hasFolder { picking = true }
            })).accessibilityIdentifier("saveToFolderToggle")
            if vault.enabled {
                if let name = vault.folderName {
                    LabeledContent("Folder", value: name).accessibilityIdentifier("saveToFolderName")
                }
                Button(vault.hasFolder ? "Change folder…" : "Choose folder…") { picking = true }
                    .accessibilityIdentifier("chooseSaveFolder")
                Label(vault.statusText, systemImage: vault.isFailing ? "exclamationmark.triangle" : "folder")
                    .font(.footnote).foregroundStyle(vault.isFailing ? .orange : .secondary)
                    .accessibilityIdentifier("saveToFolderStatus")
                if vault.isFailing || !vault.unsavedIDs.isEmpty {
                    Button("Retry") { vault.retry(history: session.history) }
                        .disabled(!vault.hasFolder).accessibilityIdentifier("retrySaveToFolder")
                }
                Button("Save all conversations now") { vault.saveAll(session.history) }
                    .disabled(!vault.hasFolder || session.history.isEmpty)
            }
        } header: { Text("Save to folder") } footer: {
            Text("Writes each conversation as one Markdown note — summary, notes and transcript with speaker "
                 + "names — when you stop or save, and updates it when a summary changes. Choose any folder in "
                 + "Files, such as an Obsidian vault. A folder in iCloud Drive is synced by Apple like your "
                 + "other files. Deleting a conversation here does not delete its note.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { vault.chooseFolder(url) }
        }
    }
}

/// The main screen's line when a note could not be written, so a failure is never only in Settings.
struct MobileVaultStatusLine: View {
    var vault: MarkdownVaultSync = MobileSession.markdownVault

    var body: some View {
        if vault.enabled, vault.isFailing {
            Label("Save to folder: " + vault.statusText, systemImage: "exclamationmark.triangle")
                .font(.caption).lineLimit(3).foregroundStyle(.orange)
                .accessibilityIdentifier("saveToFolderFailure")
        }
    }
}
