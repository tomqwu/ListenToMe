import Foundation
import Observation

/// Shared archive orchestration. Platform adapters inject secondary data owners and index updates.
/// No default paths or global services: tests and adapters choose the archive explicitly.
@MainActor @Observable
public final class ConversationRepository {
    public enum Change { case reloaded, saved(SessionRecord), cleared }
    private let archive: SessionArchive?
    public private(set) var errorText: String?
    public private(set) var archiveWarning: String?
    public private(set) var known: [SessionRecord] = []
    @ObservationIgnored public var recordsChanged: ((Change, [SessionRecord]) -> Void)?
    @ObservationIgnored public var dataOwners: [ConversationDataOwner] = []

    public init(archive: SessionArchive?, initialError: String? = nil) {
        self.archive = archive
        self.errorText = initialError
    }

    /// Readable conversations. A damaged file no longer hides the rest of the history: it is set
    /// aside by the archive and reported in `errorText` as a warning alongside the good records.
    public func all() -> [SessionRecord] {
        do {
            guard let archive else { throw CocoaError(.fileReadUnknown) }
            let result = try archive.read()
            errorText = nil
            // Sticky for the app run: the damaged file is renamed by the first scan, so a later
            // scan is clean and must not erase a note raised by an autosave's migration.
            if let warning = result.warning { archiveWarning = warning }
            known = result.records
            publishRecords(.reloaded)
            return result.records
        } catch { errorText = "Couldn't read history: \(error.localizedDescription)"; return [] }
    }

    @discardableResult
    public func add(_ record: SessionRecord) -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            // A failed legacy migration is a warning, not a failed save.
            if let warning = try archive.save(record) { archiveWarning = warning }
            if let index = known.firstIndex(where: { $0.id == record.id }) { known[index] = record } else {
                known.insert(record, at: 0)
            }
            publishRecords(.saved(record))
            errorText = nil
            return true
        } catch { errorText = "Couldn't save: \(error.localizedDescription)"; return false }
    }

    /// SwiftUI can construct and discard temporary stores while retaining its original @State.
    /// Publishing from init would replace the shared model's reader with a dead weak owner.
    /// Publish a snapshot only after an archive read/write; temporary stores cannot erase it.
    private func publishRecords(_ change: Change) { recordsChanged?(change, known) }

    /// Whether History holds this conversation.
    public func contains(_ id: String) -> Bool { archive?.contains(id: id) ?? false }

    /// Every conversation in History, or `nil` when a file could not be read, so a caller deleting what
    /// has no conversation (saved audio, #55) never mistakes an unreadable one for a missing one.
    public func completeIDs() -> Set<String>? {
        guard let result = try? archive?.read(), result.warning == nil else { return nil }
        return Set(result.records.map(\.id))
    }

    /// The user has seen the note about a set-aside file and dismissed it.
    public func dismissArchiveWarning() { archiveWarning = nil }

    /// Remove the durable record before notifying secondary owners; partial owner failures remain visible.
    @discardableResult
    public func delete(_ record: SessionRecord) -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            let result = try ConversationRemoval.remove(record, from: archive, owners: dataOwners)
            if let warning = result.archiveWarning { archiveWarning = warning }
            known.removeAll { $0.id == record.id }
            publishRecords(.reloaded)
            errorText = ConversationDataErasure.failureNote(result.failedOwners)
            return true
        } catch { errorText = "Couldn't delete conversation: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    public func clear() -> Bool {
        do {
            guard let archive else { throw CocoaError(.fileWriteUnknown) }
            // Clear deletes the quarantined files too, so any earlier warning is obsolete.
            archiveWarning = try archive.clear()
            known = []
            publishRecords(.cleared)
            let everything = ConversationDeletion(ids: [], everything: true)
            errorText = ConversationDataErasure.failureNote(ConversationDataErasure.run(dataOwners,
                                                                                        for: everything))
            return true
        } catch { errorText = "Couldn't clear history: \(error.localizedDescription)"; return false }
    }
}
