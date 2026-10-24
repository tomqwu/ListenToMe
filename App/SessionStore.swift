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
            historySearch?.update(record)
            errorText = nil
            return true
        } catch { errorText = "Couldn't save: \(error.localizedDescription)"; return false }
    }

    /// The user has seen the note about a set-aside file and dismissed it.
    func dismissArchiveWarning() { archiveWarning = nil }

    @discardableResult
    func clear() -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            // Clear deletes the quarantined files too, so any earlier warning is obsolete.
            archiveWarning = try archive.clear()
            MarkdownVaultSync.shared.forgetAll()   // A cleared conversation's note must not be written later.
            historySearch?.forgetAll()             // ...and its vectors go with it (#57).
            errorText = nil
            return true
        } catch { errorText = "Couldn't clear history: \(error.localizedDescription)"; return false }
    }
}
