import Foundation
import ListenToMeCore
import Observation

/// Settings → Save audio recordings (issue #55). Off by default. When on, each recording run writes the
/// microphone audio the transcriber heard to `SavedAudio/<conversation>/part-NNN-microphone.m4a`, always
/// excluded from iCloud and Finder backups and protected until the device is first unlocked. Apple Watch
/// recordings keep no audio: the iPhone deletes each watch chunk once its text is saved (#181).
@MainActor @Observable
final class MobileSavedAudio {
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: SavedAudioPolicy.enabledKey) }
    }
    var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: SavedAudioPolicy.retentionDaysKey)
            applyRetention()
        }
    }
    /// Why audio is not being saved, or stopped being saved; shown on the main screen until dismissed.
    private(set) var problem: String?
    /// Whether the current recording run is saving audio.
    private(set) var isSavingRun = false
    /// Bumped whenever files change, so views read the library again.
    private(set) var revision = 0
    private(set) var bytesUsed: Int64 = 0
    let recorder: SavedAudioRecorder
    let playback: SavedAudioPlayback
    @ObservationIgnored private let defaults: UserDefaults
    var library: SavedAudioLibrary { recorder.library }

    init(root: URL, defaults: UserDefaults = .standard, availableBytes: (@Sendable () -> Int64?)? = nil,
         makeWriter: SavedAudioRecorder.WriterFactory? = nil) {
        self.defaults = defaults
        enabled = SavedAudioPolicy.isEnabled(in: defaults)
        retentionDays = SavedAudioPolicy.retentionDays(in: defaults)
        let library = SavedAudioLibrary(root: root, excludeFromBackup: true)
        recorder = makeWriter.map {
            SavedAudioRecorder(library: library, availableBytes: availableBytes, makeWriter: $0)
        } ?? SavedAudioRecorder(library: library, availableBytes: availableBytes)
        playback = SavedAudioPlayback(library: library)
        recorder.onProblem = { [weak self] text in Task { @MainActor in self?.problem = text } }
        recorder.onChange = { [weak self] in Task { @MainActor in self?.refresh() } }
        applyRetention()
    }

    /// The writer for a run whose lines start at `offset`, or `nil` when the setting is off.
    func beginRun(conversation id: String, offset: TimeInterval) -> (any SavedAudioWriting)? {
        playback.stop()
        guard enabled else { isSavingRun = false; return nil }
        problem = nil
        let writer = recorder.beginRun(conversationID: id, sources: [.you], timelineOffset: offset,
                                       timesMatchAudio: true)[.you]
        isSavingRun = writer != nil
        return writer
    }

    /// The run ended; its writer was finished by the recorder.
    func endRun() { isSavingRun = false }

    func runs(for id: String) -> [SavedAudioRun] {
        _ = revision
        return library.runs(for: id)
    }

    func fileURLs(for id: String) -> [URL] {
        _ = revision
        return library.fileURLs(for: id)
    }

    /// Deletes one conversation's audio, reporting a failure on the main screen.
    func delete(conversation id: String) {
        do { try remove(ConversationDeletion(ids: [id])) } catch {
            problem = "Could not delete the saved audio: \(error.localizedDescription)"
        }
    }

    /// The saved-audio owner of a conversation deletion (`MobileSession.conversationDataOwners`):
    /// Delete removes those conversations' audio, Delete all removes every file. Each is tried.
    func remove(_ deletion: ConversationDeletion) throws {
        if deletion.ids.contains(playback.conversationID ?? "") || deletion.everything { playback.stop() }
        defer { refresh() }
        if deletion.everything { try recorder.deleteAll(); return }
        var failure: Error?
        for id in deletion.ids {
            do { try recorder.delete(conversationID: id) } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    /// Settings → Delete all saved audio. Transcripts are kept.
    func deleteAll() {
        playback.stop()
        do { try recorder.deleteAll() } catch {
            problem = "Could not delete the saved audio: \(error.localizedDescription)"
        }
        refresh()
    }

    func applyRetention(now: Date = Date()) {
        if library.deleteExpired(retentionDays: retentionDays, now: now) > 0 {
            refresh()
        } else {
            bytesUsed = library.totalBytes()
        }
    }

    func dismissProblem() { problem = nil }

    func refresh() {
        revision &+= 1
        bytesUsed = library.totalBytes()
        playback.load(conversationID: playback.conversationID)
    }
}
