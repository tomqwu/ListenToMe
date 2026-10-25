import Foundation
import Observation
import ListenToMeCore

@MainActor @Observable
final class SessionStore {
    private let repository: ConversationRepository
    let historySearch: HistorySearchModel?
    var errorText: String? { repository.errorText }
    var archiveWarning: String? { repository.archiveWarning }

    init() {
        var archive: SessionArchive?
        var initialError: String?
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
            initialError = error.localizedDescription
        }
        repository = ConversationRepository(archive: archive, initialError: initialError)
        repository.dataOwners = conversationDataOwners
        repository.recordsChanged = { [historySearch] change, records in
            historySearch?.records = { records }
            switch change {
            case .saved(let record): historySearch?.update(record)
            case .reloaded: historySearch?.sync(records)
            case .cleared: break   // The registered owner clears the index below.
            }
        }
    }

    func all() -> [SessionRecord] { repository.all() }
    @discardableResult func add(_ record: SessionRecord) -> Bool { repository.add(record) }
    func contains(_ id: String) -> Bool { repository.contains(id) }
    func completeIDs() -> Set<String>? { repository.completeIDs() }
    func dismissArchiveWarning() { repository.dismissArchiveWarning() }
    @discardableResult func clear() -> Bool { repository.clear() }

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
    func delete(_ record: SessionRecord) -> Bool { repository.delete(record) }
}
