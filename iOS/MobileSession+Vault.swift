import Foundation
import ListenToMeCore

/// Settings → Save to folder (issue #53): the hooks `save()`, the Apple Watch drain and delete call.
extension MobileSession {
    /// Where conversations are written as Markdown notes. Tests replace it.
    static var markdownVault = MarkdownVaultSync.shared

    /// Writes the note when nothing is recording: at Stop, Save, and whenever a summary, title,
    /// notes or speaker names change afterwards. Live transcript lines are not written one by one.
    /// The note's language is the one kept on the record (issue #206).
    func exportToVault(_ record: SessionRecord) {
        guard state == .idle else { return }
        let vault = Self.markdownVault
        guard vault.enabled else { return }
        vault.save(record)
        // Notes left unwritten before a relaunch are picked up again from History.
        if vault.unsavedIDs.count > vault.pending.count {
            vault.retry(history: history)
        }
    }

    /// Deleted conversations' queued notes are dropped, so a later Retry cannot write them. Notes
    /// already in the folder stay: the folder belongs to the user.
    func forgetVaultNotes(_ deletion: ConversationDeletion) {
        if deletion.everything { Self.markdownVault.forgetAll(); return }
        deletion.ids.forEach { Self.markdownVault.forget(id: $0) }
    }

    /// The conversation Save all and Retry must not write: the one being recorded.
    var vaultRecordingID: String? { state == .idle ? nil : id }
}
