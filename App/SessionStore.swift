import Foundation
import Observation
import ListenToMeCore

@MainActor
@Observable
final class SessionStore {
    private let archive: SessionArchive?
    private(set) var errorText: String?
    /// A damaged history file or legacy file the archive set aside. Separate from `errorText`,
    /// which only the failure paths read: the first migration usually happens during an autosave,
    /// so the warning has to survive until History is opened.
    private(set) var archiveWarning: String?

    init() {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            let legacy = base.appendingPathComponent("ListenToMe/sessions.json")
            let folder = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "ListenToMe Dev" : "ListenToMe"
            archive = SessionArchive(directory: base.appendingPathComponent(folder + "/Conversations"), legacyURL: legacy,
                                     ownsLegacyFile: folder == "ListenToMe")
        } catch {
            archive = nil
            errorText = error.localizedDescription
        }
    }

    /// Readable conversations. A damaged file no longer hides the rest of the history: it is set
    /// aside by the archive and reported in `errorText` as a warning alongside the good records.
    func all() -> [SessionRecord] {
        do {
            guard let archive else { throw CocoaError(.fileReadUnknown) }
            let result = try archive.read()
            errorText = nil
            // Sticky for the app run: the damaged file is renamed by the first scan, so a later
            // scan is clean and must not erase a note raised by an autosave's migration.
            if let warning = result.warning { archiveWarning = warning }
            return result.records
        } catch { errorText = "Couldn't read history: \(error.localizedDescription)"; return [] }
    }

    @discardableResult
    func add(_ record: SessionRecord) -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            // A failed legacy migration is a warning, not a failed save.
            if let warning = try archive.save(record) { archiveWarning = warning }
            errorText = nil
            return true
        } catch { errorText = "Couldn't save: \(error.localizedDescription)"; return false }
    }

    /// Whether History holds this conversation.
    func contains(_ id: String) -> Bool { archive?.contains(id: id) ?? false }

    /// Every conversation in History, or `nil` when a file could not be read, so a caller deleting what
    /// has no conversation (saved audio, #55) never mistakes an unreadable one for a missing one.
    func completeIDs() -> Set<String>? {
        guard let result = try? archive?.read(), result.warning == nil else { return nil }
        return Set(result.records.map(\.id))
    }

    /// The user has seen the note about a set-aside file and dismissed it.
    func dismissArchiveWarning() { archiveWarning = nil }

    /// Everything a conversation owns on this Mac besides its archive record, removed after the records
    /// by the same Core list iOS uses (#220). New per-conversation storage registers here.
    var conversationDataOwners: [ConversationDataOwner] {
        [
            // A cleared conversation's note must not be written later.
            ConversationDataOwner("Save to folder queue") { deletion in
                if deletion.everything {
                    MarkdownVaultSync.shared.forgetAll()
                } else {
                    deletion.ids.forEach(MarkdownVaultSync.shared.forget(id:))
                }
            },
            ConversationDataOwner("saved audio") { try MacSavedAudio.shared.remove($0) },   // #55
        ]
    }

    @discardableResult
    func clear() -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            let ids = ((try? archive.read().records) ?? []).map(\.id)
            // Clear deletes the quarantined files too, so any earlier warning is obsolete.
            archiveWarning = try archive.clear()
            let failed = ConversationDataErasure.run(conversationDataOwners,
                                                     for: ConversationDeletion(ids: ids, everything: true))
            if let note = ConversationDataErasure.failureNote(failed) { archiveWarning = note }
            errorText = nil
            return true
        } catch { errorText = "Couldn't clear history: \(error.localizedDescription)"; return false }
    }
}
