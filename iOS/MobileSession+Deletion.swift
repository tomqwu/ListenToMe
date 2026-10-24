import Foundation
import ListenToMeCore

/// Deleting conversations: History's Delete, and Delete all conversations from History or Settings
/// (#220). Both go through `eraseConversations(_:deleted:)`, which removes the archive records and
/// then runs every entry of `conversationDataOwners`.
extension MobileSession {
    /// Everything a conversation owns besides its archive record. **New per-conversation storage
    /// registers here** — saved audio (#55) and the semantic search index (#57) each add an owner —
    /// and is then removed by Delete and by Delete all alike. An owner that throws is reported once
    /// the records are gone; the other owners still run.
    var conversationDataOwners: [ConversationDataOwner] {
        [
            ConversationDataOwner("attachments") { [unowned self] in try removeAttachmentFiles($0) },
            ConversationDataOwner("Apple Watch audio") { [unowned self] in
                try discardWatchAudio(sourceImportIDs: $0.sourceImportIDs)
            },
            ConversationDataOwner("shared imports") { [unowned self] in try removeImportedShares($0) },
            ConversationDataOwner("Save to folder queue") { [unowned self] in forgetVaultNotes($0) },
            ConversationDataOwner("search index") { [unowned self] in
                forgetSearchIndex(ids: $0.ids, everything: $0.everything)
            },
        ]
    }

    func deleteConversation(id targetID: String) {
        let source = history.first { $0.id == targetID }?.sourceImportID ?? (targetID == id ? sourceImportID : nil)
        eraseConversations(ConversationDeletion(ids: [targetID], sourceImportIDs: source.map { [$0] } ?? []),
                           deleted: "Conversation and attachments deleted from this device.")
    }

    /// Not while recording, stopping or generating, and only when History has something to delete.
    var canDeleteAllConversations: Bool { !busy && !history.isEmpty }

    /// Every saved conversation and the open one, which starts over as a new conversation.
    func deleteAllConversations() {
        guard canDeleteAllConversations else { return }
        let count = history.count
        let deletion = ConversationDeletion(ids: history.map(\.id) + [id],
                                            sourceImportIDs: history.compactMap(\.sourceImportID)
                                                + (sourceImportID.map { [$0] } ?? []),
                                            everything: true)
        eraseConversations(deletion, deleted: count == 1 ? "1 conversation deleted from this device."
                                                          : "\(count) conversations deleted from this device.")
    }

    static func deleteAllTitle(count: Int) -> String {
        count == 1 ? "Delete 1 conversation?" : "Delete all \(count) conversations?"
    }

    /// The confirmation says what goes, what stays, and that it cannot be undone.
    static func deleteAllMessage(vaultFolder: String?, watchWaiting: Bool) -> String {
        var parts = ["This removes every conversation's transcript, notes, attachments, AI outputs and "
                     + "Apple Watch audio from this device."]
        if watchWaiting { parts.append("Recordings still waiting from Apple Watch are kept.") }
        if let vaultFolder {
            parts.append("Notes already saved to “\(vaultFolder)” stay there; ListenToMe never deletes your folder's files.")
        }
        parts.append("It cannot be undone.")
        return parts.joined(separator: " ")
    }

    var deleteAllMessage: String {
        let vault = Self.markdownVault
        return Self.deleteAllMessage(vaultFolder: vault.enabled ? (vault.folderName ?? "your folder") : nil,
                                     watchWaiting: !watchInboxRows.isEmpty)
    }

    /// The one deletion path. The archive is the commit point: if its records cannot be removed,
    /// nothing else is touched and the open conversation is saved back. After it, every owner runs.
    @discardableResult
    private func eraseConversations(_ deletion: ConversationDeletion, deleted: String) -> Bool {
        guard !busy else { return false }
        pendingSave?.cancel(); pendingSave = nil
        lastSavedData = nil
        let deletingActive = deletion.ids.contains(id)
        let empty = SessionRecord(id: UUID().uuidString, title: "New conversation", date: Date(),
                                  transcript: "", summary: "", segments: [], notes: "")
        do {
            // Persist an empty active snapshot first so a deleted conversation cannot return on relaunch.
            if deletingActive {
                try PrivateStorage.createDirectory(at: activeURL.deletingLastPathComponent())
                try JSONEncoder().encode(empty).write(to: activeURL, options: PrivateStorage.writingOptions)
                try? PrivateStorage.setExcludedFromBackup(excludeFromBackup, at: activeURL)
            }
            // Clear also takes history files set aside as unreadable. The folders stay, with their
            // backup choice.
            if deletion.everything { try archive.clear() } else { for id in deletion.ids { try archive.delete(id: id) } }
        } catch {
            if deletingActive { save(announce: false) }
            reloadHistory()
            message = "Could not delete \(deletion.everything ? "conversations" : "conversation"): "
                + error.localizedDescription
            return false
        }
        let failed = ConversationDataErasure.run(conversationDataOwners, for: deletion)
        if deletingActive { restore(empty) }
        reloadHistory()
        archiveWarning = nil   // the user has acted on History; the note has served its purpose
        message = ConversationDataErasure.failureNote(failed) ?? deleted
        return true
    }

    private func removeAttachmentFiles(_ deletion: ConversationDeletion) throws {
        let folders: [URL]
        if deletion.everything {
            // Every conversation's folder, including one only an unreadable record pointed to.
            folders = ((try? FileManager.default.contentsOfDirectory(at: attachmentRoot, includingPropertiesForKeys: nil))
                ?? []) + [Self.attachmentPresentationRoot]
        } else {
            folders = deletion.ids.flatMap { [attachmentStore(for: $0).directory, attachmentPresentationDirectory(for: $0)] }
        }
        try Self.removeItems(folders)
    }

    /// A share whose conversation was saved but whose inbox folder could not be removed stays in the
    /// App Group inbox; with the conversation gone, the next drain would import it again. Delete all
    /// also drops shares set aside as unimportable, which would otherwise wait a day. Shares not yet
    /// imported are new content and stay.
    private func removeImportedShares(_ deletion: ConversationDeletion) throws {
        guard let root = sharedInboxRoot,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }
        let imported = Set(deletion.sourceImportIDs)
        try Self.removeItems(folders.filter { folder in
            if folder.lastPathComponent == Self.failedInboxFolder { return deletion.everything }
            return Self.sharedImportID(in: folder).map(imported.contains) ?? false
        })
    }

    private static func sharedImportID(in folder: URL) -> String? {
        let manifest = folder.appendingPathComponent("manifest.json")
        guard (try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }) ?? .max < 2 * 1024 * 1024,
              let data = try? Data(contentsOf: manifest) else { return nil }
        return (try? JSONDecoder().decode(SharedImport.self, from: data))?.id
    }

    /// Removes each item that exists; every one is tried, and the first failure is thrown.
    private static func removeItems(_ urls: [URL]) throws {
        var failure: Error?
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }
}
