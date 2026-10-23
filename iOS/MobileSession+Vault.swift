import Foundation
import ListenToMeCore

/// Settings → Save to folder (issue #53): the hook `save()` calls after a conversation reaches History.
extension MobileSession {
    /// Where conversations are written as Markdown notes. Tests replace it.
    static var markdownVault = MarkdownVaultSync.shared

    /// Writes the note when the conversation is not recording: at Stop, Save, and whenever a summary,
    /// title, notes or speaker names change afterwards. Live transcript lines are not written one by one.
    func exportToVault(_ record: SessionRecord) {
        guard state == .idle else { return }
        let vault = Self.markdownVault
        vault.save(record, language: conversationLanguage)
        // Notes left unwritten before a relaunch are picked up again from History.
        if vault.unsavedIDs.count > vault.pending.count { vault.retry(history: history) }
    }
}
