import Foundation
import ListenToMeCore
import Observation

/// "Save to folder" (issue #53): after a conversation is saved, write it as one Markdown note into a
/// folder the user chose, such as an Obsidian vault or a folder in iCloud Drive. Off by default.
///
/// The latest version of each conversation waits in `pending` until it is written, so a failure is
/// retried on the next save or from Retry, and is shown in Settings and on the main screen. The IDs
/// of unwritten notes survive relaunch; Retry rebuilds them from History. A failure about one note
/// (an iCloud placeholder, a name another note holds) never holds up the others; a failure about the
/// folder (gone, no access, disk full) stops the queue until the folder is usable again.
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
    /// The last failure of each note that failed on its own; the note stays queued.
    private(set) var noteFailures: [String: MarkdownVaultFailure] = [:]
    /// The conversation being recorded, which Retry and Save all leave alone (macOS sets it from
    /// its checkpoint; iOS passes `excluding:`).
    @ObservationIgnored var activeRecordingID: String?
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
    /// Whether the main screen should show the status line: a failure, or notes waiting to be
    /// written (no folder chosen yet, or left over from before a relaunch).
    var needsAttention: Bool { enabled && (isFailing || (!unsavedIDs.isEmpty && status != .saving)) }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if !on {
            generation += 1; drainTask?.cancel(); drainTask = nil
            pending = [:]; noteFailures = [:]; unsavedIDs = []; persistUnsaved()
        }
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
            noteFailures = [:]
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
    func save(_ record: SessionRecord, language: String? = nil, startedAt: Date? = nil) {
        guard enabled else { return }
        pending[record.id] = MarkdownVault.note(for: record, language: language, startedAt: startedAt)
        markUnsaved(record.id, true)
        guard writer != nil else { status = .needsFolder; return }
        drain()
    }

    /// Writes every conversation in History, for a folder chosen after conversations already exist.
    /// `language` is the one ordinary saves use, so the front matter does not change between them.
    func saveAll(_ records: [SessionRecord], language: String? = nil, excluding: String? = nil) {
        guard enabled else { return }
        for record in records where pending[record.id] == nil && !isRecording(record.id, excluding) {
            pending[record.id] = MarkdownVault.note(for: record, language: language)
            markUnsaved(record.id, true)
        }
        guard writer != nil else { status = .needsFolder; return }
        drain()
    }

    /// Tries the waiting notes again. Notes that were waiting before a relaunch come back from History.
    func retry(history: [SessionRecord], language: String? = nil, excluding: String? = nil) {
        guard enabled else { return }
        for record in history where unsavedIDs.contains(record.id) && pending[record.id] == nil
            && !isRecording(record.id, excluding) {
            pending[record.id] = MarkdownVault.note(for: record, language: language)
        }
        // A conversation deleted from History since cannot be written any more.
        let recording = [excluding, activeRecordingID].compactMap { $0 }
        unsavedIDs.formIntersection(Set(pending.keys).union(recording))
        persistUnsaved()
        noteFailures = noteFailures.filter { pending[$0.key] != nil }
        guard writer != nil else { status = .needsFolder; return }
        if pending.isEmpty { refreshIdleStatus() } else { drain() }
    }

    /// The conversation was deleted: its note must never be written from the queue afterwards.
    /// A note already in the folder stays there; the folder belongs to the user.
    func forget(id: String) {
        pending[id] = nil
        noteFailures[id] = nil
        markUnsaved(id, false)
        settleStatusAfterRemoval()
    }

    /// History was cleared.
    func forgetAll() {
        pending = [:]; noteFailures = [:]; unsavedIDs = []; persistUnsaved()
        settleStatusAfterRemoval()
    }

    /// Waits for the queued writes, at most `timeout`. macOS calls it before it quits.
    func waitForWrites(timeout: Duration) async {
        guard let task = drainTask else { return }
        let gate = OnceGate()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Task { await task.value; gate.open(done) }
            Task { try? await Task.sleep(for: timeout); gate.open(done) }
        }
    }

    var statusText: String {
        let folder = folderName.map { "“\($0)”" } ?? "the folder"
        switch status {
        case .off: return "Off. Conversations stay inside ListenToMe."
        case .needsFolder:
            return unsavedIDs.isEmpty ? "Choose a folder to start saving notes."
                : "\(unsavedIDs.count) conversation(s) waiting. Choose a folder in Settings to save them."
        case .ready:
            if !unsavedIDs.isEmpty {
                return "\(unsavedIDs.count) conversation(s) not saved to \(folder) yet. Tap Retry."
            }
            return "Saving each conversation to \(folder) when you stop or save."
        case .saving: return "Saving to \(folder)…"
        case .saved(let name, let date):
            let saved = "Saved “\(name)” at \(date.formatted(date: .omitted, time: .shortened))."
            return unsavedIDs.isEmpty ? saved : saved + " \(unsavedIDs.count) more not saved yet. Tap Retry."
        case .failed(let failure):
            let others = noteFailures.count - (noteFailures.values.contains(failure) ? 1 : 0)
            return others > 0 ? failure.message + " \(others) more conversation(s) also not saved." : failure.message
        }
    }

    private func isRecording(_ id: String, _ excluding: String?) -> Bool {
        id == excluding || id == activeRecordingID
    }

    private func refreshIdleStatus() {
        status = !enabled ? .off : writer == nil ? .needsFolder : .ready
    }

    /// After a note left the queue: a failure that was only about removed notes no longer applies.
    private func settleStatusAfterRemoval() {
        guard case .failed(let failure) = status, !failure.stopsQueue else { return }
        if let next = noteFailures.values.first { status = .failed(next) } else { refreshIdleStatus() }
    }

    private func markUnsaved(_ id: String, _ unsaved: Bool) {
        let changed = unsaved ? unsavedIDs.insert(id).inserted : unsavedIDs.remove(id) != nil
        if changed { persistUnsaved() }
    }

    private func persistUnsaved() { defaults.set(unsavedIDs.sorted(), forKey: Self.unsavedKey) }

    /// Writes each waiting note once per pass. A per-note failure is recorded and the pass goes on;
    /// a folder failure stops it with every note still queued.
    private func drain() {
        guard drainTask == nil, let writer, enabled, !pending.isEmpty else { return }
        let generation = generation
        status = .saving   // At once, so a Retry visibly replaces the old failure.
        drainTask = Task { [weak self] in
            var attempted = Set<String>()
            var lastSaved: Status?
            while let self, self.generation == generation,
                  let (id, note) = self.pending.first(where: { !attempted.contains($0.key) }) {
                attempted.insert(id)
                self.status = .saving
                let outcome = await writer.save(note)
                guard self.generation == generation else { return }
                let refreshed = await writer.bookmark
                if self.defaults.data(forKey: Self.bookmarkKey) != refreshed {
                    self.defaults.set(refreshed, forKey: Self.bookmarkKey)
                }
                switch outcome {
                case .saved(let name), .unchanged(let name):
                    if self.pending[id] == note {
                        self.pending[id] = nil
                        self.noteFailures[id] = nil
                        self.markUnsaved(id, false)
                    } else if self.pending[id] != nil {
                        attempted.remove(id)   // A newer version arrived during the write.
                    }
                    lastSaved = .saved(fileName: name, at: Date())
                case .failed(let failure):
                    if failure.stopsQueue {
                        self.status = .failed(failure)
                        self.drainTask = nil
                        return
                    }
                    if self.pending[id] != nil { self.noteFailures[id] = failure }
                }
            }
            guard let self, self.generation == generation else { return }
            self.drainTask = nil
            if let failure = self.noteFailures.values.first { self.status = .failed(failure) }
            else if let lastSaved { self.status = lastSaved }
            else { self.refreshIdleStatus() }
        }
    }
}

/// Resumes a continuation once, whichever of two tasks gets there first.
@MainActor
private final class OnceGate {
    private var opened = false
    func open(_ continuation: CheckedContinuation<Void, Never>) {
        guard !opened else { return }
        opened = true
        continuation.resume()
    }
}
