import Foundation
import ListenToMeCore

/// Settings → Save to folder (issue #53): the hooks `save()`, the Apple Watch drain and delete call.
extension MobileSession {
    /// Where conversations are written as Markdown notes. Tests replace it.
    static var markdownVault = MarkdownVaultSync.shared

    /// Writes the note when nothing is recording: at Stop, Save, and whenever a summary, title,
    /// notes or speaker names change afterwards. Live transcript lines are not written one by one.
    /// `language` defaults to the open conversation's; the Apple Watch drain passes its own.
    func exportToVault(_ record: SessionRecord, language: String? = nil) {
        guard state == .idle else { return }
        let vault = Self.markdownVault
        guard vault.enabled else { return }
        vault.save(record, language: language ?? conversationLanguage)
        // Notes left unwritten before a relaunch are picked up again from History.
        if vault.unsavedIDs.count > vault.pending.count {
            vault.retry(history: history, language: conversationLanguage)
        }
    }

    /// A deleted conversation's queued note is dropped, so a later Retry cannot write it.
    func forgetVaultNote(_ id: String) { Self.markdownVault.forget(id: id) }

    /// The conversation Save all and Retry must not write: the one being recorded.
    var vaultRecordingID: String? { state == .idle ? nil : id }
}
