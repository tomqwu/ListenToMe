import Foundation
import ListenToMeCore
import Observation

/// "Save to folder" (issue #53): after a conversation is saved, write it as one Markdown note into a
/// folder the user chose, such as an Obsidian vault or a folder in iCloud Drive. Off by default.
///
/// The latest version of each conversation waits in `pending` until it is written, so a failure is
/// retried on the next save or from Retry, and is shown in Settings and on the main screen. The IDs
/// of unwritten notes survive relaunch; Retry rebuilds them from History.
@MainActor @Observable
final class MarkdownVaultSync {
    static let shared = MarkdownVaultSync()

    enum Status: Equatable {
        case off
        case needsFolder
        case ready
        case saving
        case saved(fileName: String, at: Date)
        case failed(MarkdownVaultFailure)
    }

    static let enabledKey = "markdownVaultEnabled"
    static let bookmarkKey = "markdownVaultBookmark"
    static let unsavedKey = "markdownVaultUnsavedIDs"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeWriter: (Data) -> MarkdownVaultWriter
    private(set) var enabled: Bool
    private(set) var folderName: String?
    private(set) var status: Status = .off
    /// Notes waiting to be written, newest version per conversation.
    private(set) var pending: [String: MarkdownVaultNote] = [:]
    /// Conversations not yet written, including ones from before a relaunch that only History holds.
    private(set) var unsavedIDs: Set<String>
    @ObservationIgnored private var writer: MarkdownVaultWriter?
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    /// Bumped when the folder changes, so a write already under way cannot report on the new folder.
    @ObservationIgnored private var generation = 0

    init(defaults: UserDefaults = .standard,
         makeWriter: @escaping (Data) -> MarkdownVaultWriter = { MarkdownVaultWriter(bookmark: $0) }) {
        self.defaults = defaults
        self.makeWriter = makeWriter
        enabled = defaults.bool(forKey: Self.enabledKey)
        unsavedIDs = Set(defaults.stringArray(forKey: Self.unsavedKey) ?? [])
        if let bookmark = defaults.data(forKey: Self.bookmarkKey) {
            writer = makeWriter(bookmark)
            folderName = MarkdownVaultWriter.folderName(for: bookmark)
        }
        refreshIdleStatus()
    }

    var hasFolder: Bool { writer != nil }
    var isFailing: Bool { if case .failed = status { return true }; return false }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if !on { generation += 1; drainTask?.cancel(); drainTask = nil; pending = [:] }
        refreshIdleStatus()
    }

    /// Stores a folder the user picked. On iOS the picked URL is security-scoped: the bookmark has
    /// to be made while that access is held.
    @discardableResult
    func chooseFolder(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try MarkdownVaultWriter.makeBookmark(for: url)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            generation += 1
            drainTask?.cancel(); drainTask = nil
            writer = makeWriter(bookmark)
            folderName = url.lastPathComponent
            refreshIdleStatus()
            drain()
            return true
        } catch {
            status = .failed(MarkdownVaultFailure(kind: .accessDenied, message:
                "Couldn't use “\(url.lastPathComponent)”: \(error.localizedDescription) Choose another folder."))
            return false
        }
    }

    func forgetFolder() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        generation += 1
        drainTask?.cancel(); drainTask = nil
        writer = nil; folderName = nil
        refreshIdleStatus()
    }

    /// Queues the conversation's note. Callers skip this while recording: notes are written at
    /// Stop, Save and when a summary or edit changes a stopped conversation.
    func save(_ record: SessionRecord, language: String? = nil) {
        guard enabled else { return }
        pending[record.id] = MarkdownVault.note(for: record, language: language)
        markUnsaved(record.id, true)
        guard writer != nil else { status = .needsFolder; return }
        drain()
    }

    /// Writes every conversation in History, for a folder chosen after conversations already exist.
    func saveAll(_ records: [SessionRecord]) {
        guard enabled else { return }
        for record in records where pending[record.id] == nil {
            pending[record.id] = MarkdownVault.note(for: record)
            markUnsaved(record.id, true)
        }
        guard writer != nil else { status = .needsFolder; return }
        drain()
    }

    /// Tries the waiting notes again. Notes that were waiting before a relaunch come back from History.
    func retry(history: [SessionRecord]) {
        for record in history where unsavedIDs.contains(record.id) && pending[record.id] == nil {
            pending[record.id] = MarkdownVault.note(for: record)
        }
        // A conversation deleted from History since cannot be written any more.
        unsavedIDs.formIntersection(Set(pending.keys))
        persistUnsaved()
        if pending.isEmpty { refreshIdleStatus() } else { drain() }
    }

    var statusText: String {
        let folder = folderName.map { "“\($0)”" } ?? "the folder"
        switch status {
        case .off: return "Off. Conversations stay inside ListenToMe."
        case .needsFolder: return "Choose a folder to start saving notes."
        case .ready:
            if !unsavedIDs.isEmpty {
                return "\(unsavedIDs.count) conversation(s) not saved to \(folder) yet. Tap Retry."
            }
            return "Saving each conversation to \(folder) when you stop or save."
        case .saving: return "Saving to \(folder)…"
        case .saved(let name, let date):
            let saved = "Saved “\(name)” at \(date.formatted(date: .omitted, time: .shortened))."
            return unsavedIDs.isEmpty ? saved : saved + " \(unsavedIDs.count) more not saved yet. Tap Retry."
        case .failed(let failure): return failure.message
        }
    }

    private func refreshIdleStatus() {
        status = !enabled ? .off : writer == nil ? .needsFolder : .ready
    }

    private func markUnsaved(_ id: String, _ unsaved: Bool) {
        let changed = unsaved ? unsavedIDs.insert(id).inserted : unsavedIDs.remove(id) != nil
        if changed { persistUnsaved() }
    }

    private func persistUnsaved() { defaults.set(unsavedIDs.sorted(), forKey: Self.unsavedKey) }

    /// Writes waiting notes one at a time. Stops at the first failure and keeps every note queued.
    private func drain() {
        guard drainTask == nil, let writer, enabled else { return }
        let generation = generation
        drainTask = Task { [weak self] in
            while let self, self.generation == generation, let (id, note) = self.pending.first {
                self.status = .saving
                let outcome = await writer.save(note)
                guard self.generation == generation else { return }
                let refreshed = await writer.bookmark
                if self.defaults.data(forKey: Self.bookmarkKey) != refreshed {
                    self.defaults.set(refreshed, forKey: Self.bookmarkKey)
                }
                switch outcome {
                case .saved(let name), .unchanged(let name):
                    // A newer version queued during the write stays queued.
                    if self.pending[id] == note {
                        self.pending[id] = nil
                        self.markUnsaved(id, false)
                    }
                    self.status = .saved(fileName: name, at: Date())
                case .failed(let failure):
                    self.status = .failed(failure)
                    self.drainTask = nil
                    return
                }
            }
            if self?.generation == generation { self?.drainTask = nil }
        }
    }
}
