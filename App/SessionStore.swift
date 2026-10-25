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
    /// The on-device semantic index beside this archive (#57). Dev and Release builds keep separate
    /// archives ("ListenToMe Dev" vs "ListenToMe"), so they keep separate indexes too.
    let historySearch: HistorySearchModel?
    /// The conversations as last read or saved; what History search and Ask read (#57).
    @ObservationIgnored private var known: [SessionRecord] = []

    init() {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            let legacy = base.appendingPathComponent("ListenToMe/sessions.json")
            let folder = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "ListenToMe Dev" : "ListenToMe"
            let conversations = base.appendingPathComponent(folder + "/Conversations")
            archive = SessionArchive(directory: conversations, legacyURL: legacy,
                                     ownsLegacyFile: folder == "ListenToMe")
            historySearch = HistorySearchModel.shared(besideArchive: conversations)
        } catch {
            archive = nil
            historySearch = nil
            errorText = error.localizedDescription
        }
        historySearch?.records = { [weak self] in self?.known ?? [] }
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
            known = result.records
            historySearch?.sync(result.records)   // vectors of anything no longer here are dropped
            return result.records
        } catch { errorText = "Couldn't read history: \(error.localizedDescription)"; return [] }
    }

    @discardableResult
    func add(_ record: SessionRecord) -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            // A failed legacy migration is a warning, not a failed save.
            if let warning = try archive.save(record) { archiveWarning = warning }
            if let index = known.firstIndex(where: { $0.id == record.id }) { known[index] = record } else {
                known.insert(record, at: 0)
            }
            historySearch?.update(record)
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

    /// Everything a conversation owns besides its archive file, as on iOS (#220). **New
    /// per-conversation storage registers here**, so deleting conversations removes it too.
    var conversationDataOwners: [ConversationDataOwner] {
        [
            // A deleted conversation's note must not be written later.
            ConversationDataOwner("Save to folder queue") { deletion in
                if deletion.everything { MarkdownVaultSync.shared.forgetAll() } else {
                    deletion.ids.forEach(MarkdownVaultSync.shared.forget(id:))
                }
            },
            ConversationDataOwner("search index") { [historySearch] deletion in   // #57
                if deletion.everything { historySearch?.forgetAll() } else {
                    deletion.ids.forEach { historySearch?.forget(id: $0) }
                }
            },
            ConversationDataOwner("saved audio") { try MacSavedAudio.shared.remove($0) },   // #55
        ]
    }

    @discardableResult
    func delete(_ record: SessionRecord) -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            let result = try ConversationRemoval.remove(record, from: archive, owners: conversationDataOwners)
            if let warning = result.archiveWarning { archiveWarning = warning }
            known.removeAll { $0.id == record.id }
            errorText = ConversationDataErasure.failureNote(result.failedOwners)
            return true
        } catch { errorText = "Couldn't delete conversation: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func clear() -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            // Clear deletes the quarantined files too, so any earlier warning is obsolete.
            archiveWarning = try archive.clear()
            known = []
            let everything = ConversationDeletion(ids: [], everything: true)
            errorText = ConversationDataErasure.failureNote(ConversationDataErasure.run(conversationDataOwners,
                                                                                        for: everything))
            return true
        } catch { errorText = "Couldn't clear history: \(error.localizedDescription)"; return false }
    }
}
