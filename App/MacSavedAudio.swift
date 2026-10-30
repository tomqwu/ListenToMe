import AppKit
import Foundation
import Observation
import SwiftUI
import ListenToMeCore

/// The half of Save audio recordings (issue #55) that the capture closure uses: which conversation the
/// next capture saves into (none when the setting is off or the conversation will not be saved), and
/// where that recording's lines start on the conversation's timeline.
final class MacSavedAudioRuns: @unchecked Sendable {
    let recorder: SavedAudioRecorder
    private let lock = NSLock()
    private var conversationID: String?
    /// The session's `recordingOffset`, read as its capture is made (after `startRecordingTimeline`).
    @MainActor var timelineOffset: () -> TimeInterval = { 0 }

    init(recorder: SavedAudioRecorder) { self.recorder = recorder }

    func prepare(conversationID: String?) { lock.withLock { self.conversationID = conversationID } }

    /// One writer for the microphone and one for system audio, each its own labelled file, placed where
    /// this recording's lines start (#233 moves every recording after the first along the timeline).
    /// Line times match the audio only with WhisperKit; Apple's engines report none, so those lines
    /// cannot seek.
    @MainActor
    func writersForNewCapture(timesMatchAudio: Bool) -> [SpeakerSource: any SavedAudioWriting] {
        guard let id = lock.withLock({ conversationID }) else {
            recorder.forgetLatestRun()
            return [:]
        }
        return recorder.beginRun(conversationID: id, sources: [.you, .others], timelineOffset: timelineOffset(),
                                 timesMatchAudio: timesMatchAudio)
    }
}

/// Settings → Save audio recordings on the Mac. Off by default. Each recording run writes
/// `part-NNN-microphone.m4a` and `part-NNN-system.m4a` under Application Support; they follow Time
/// Machine like the conversations beside them, are deleted by Clear history, Delete all saved audio,
/// Discard or Close without saving, or the chosen retention, and never leave the Mac unless the user
/// shares them. Audio is saved only for a conversation that is saved: with Save sessions off, none.
@MainActor @Observable
final class MacSavedAudio {
    static let shared = MacSavedAudio()

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: SavedAudioPolicy.enabledKey)
            if oldValue, !enabled { stopSavingNow() }
        }
    }
    var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: SavedAudioPolicy.retentionDaysKey)
            applyRetention()
        }
    }
    private(set) var problem: String?
    private(set) var bytesUsed: Int64 = 0
    private(set) var revision = 0
    let runs: MacSavedAudioRuns
    let playback: SavedAudioPlayback
    var library: SavedAudioLibrary { runs.recorder.library }
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)?

    /// Isolated native-view tests supply a temporary library; never open user storage,
    /// install app observers or apply retention while constructing that test owner.
    init(library: SavedAudioLibrary) {
        enabled = false
        retentionDays = 0
        runs = MacSavedAudioRuns(recorder: SavedAudioRecorder(library: library))
        playback = SavedAudioPlayback(library: library)
    }

    private init() {
        enabled = SavedAudioPolicy.isEnabled()
        retentionDays = SavedAudioPolicy.retentionDays()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "ListenToMe Dev" : "ListenToMe"
        let library = SavedAudioLibrary(root: base.appendingPathComponent(folder + "/SavedAudio", isDirectory: true),
                                        excludeFromBackup: false)
        let recorder = SavedAudioRecorder(library: library)
        runs = MacSavedAudioRuns(recorder: recorder)
        playback = SavedAudioPlayback(library: library)
        recorder.onProblem = { text in Task { @MainActor in MacSavedAudio.shared.problem = text } }
        recorder.onChange = { Task { @MainActor in MacSavedAudio.shared.refresh() } }
        applyRetention()
        // Retention also runs each time the app comes forward, so a Mac left open for weeks still deletes.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in MacSavedAudio.shared.applyRetention() }
            }
    }

    /// Called right before each capture starts. `conversationID` is `nil` when this conversation will
    /// not be saved to History, so its audio is not saved either.
    func prepareRun(conversationID: String?) {
        runs.prepare(conversationID: enabled ? conversationID : nil)
        if enabled { problem = nil }
        playback.stop()
    }

    /// The run's first transcript line, known once the capture has started.
    func anchorRun(firstSegment: Int) { runs.recorder.anchorLatestRun(firstSegment: firstSegment) }

    /// Turned off mid-recording: the running files stop at once and keep what they already have.
    private func stopSavingNow() {
        runs.prepare(conversationID: nil)
        guard runs.recorder.recordingConversation != nil else { return }
        problem = "Saving audio is off. The audio recorded until now is kept; delete it in Settings."
        let recorder = runs.recorder
        Task { await recorder.finishAll() }
    }

    /// Stop and quit wait, briefly, for the files to close.
    func waitForWrites() async { await runs.recorder.waitForWrites(timeout: .seconds(5)) }

    /// Discard and Close without saving: the conversation is not kept, so neither is its audio.
    func discard(conversationID: String) {
        do { try runs.recorder.delete(conversationID: conversationID) } catch {
            problem = "Could not delete the saved audio: \(error.localizedDescription)"
        }
        refresh()
    }

    /// At launch: repairs runs the app was killed in and deletes audio whose conversation is gone.
    /// `keeping` is `nil` when History could not be read completely, so nothing counts as an orphan.
    func tidy(keeping: Set<String>?) {
        let recording = runs.recorder.recordingConversation
        library.repairUnfinished(skipping: recording, duration: SavedAudioFileWriter.playableDuration)
        if var keeping {
            if let recording { keeping.insert(recording) }
            library.deleteOrphans(keeping: keeping)
        }
        applyRetention()
    }

    /// The saved-audio owner of Clear history (`SessionStore.conversationDataOwners`). Clearing while a
    /// recording saves audio deletes that recording's audio too, and says so.
    func remove(_ deletion: ConversationDeletion) throws {
        playback.stop()
        defer { refresh() }
        if let recording = runs.recorder.recordingConversation,
           deletion.everything || deletion.ids.contains(recording) {
            problem = "Saved audio deleted with the history. This recording's audio is no longer being saved."
        }
        if deletion.everything { try runs.recorder.deleteAll(); return }
        var failure: Error?
        for id in deletion.ids {
            do { try runs.recorder.delete(conversationID: id) } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    /// Settings → Delete all saved audio; history is kept. Not while a recording saves audio.
    func deleteAll() {
        guard runs.recorder.recordingConversation == nil else { return }
        playback.stop()
        do { try runs.recorder.deleteAll() } catch {
            problem = "Could not delete the saved audio: \(error.localizedDescription)"
        }
        refresh()
    }

    func applyRetention(now: Date = Date()) {
        library.deleteExpired(retentionDays: retentionDays, now: now)
        refresh()
    }

    func dismissProblem() { problem = nil }

    func refresh() {
        revision &+= 1
        bytesUsed = library.totalBytes()
        playback.load(conversationID: playback.conversationID)
    }
}

/// Settings → Save audio recordings. Applied immediately, like Save to folder.
struct MacSavedAudioSettings: View {
    @Bindable var audio = MacSavedAudio.shared
    @State private var confirmDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Save audio recordings (microphone and system audio)", isOn: $audio.enabled)
            Text("Off by default. When on, each recording saves the microphone and system audio as two files with "
                 + "its conversation on this Mac, so you can play them back and share them. They are never "
                 + "uploaded. \(SavedAudioPolicy.estimateText(tracks: 2)) with system audio. Clear history "
                 + "deletes them too, and Discard deletes a conversation's audio. Audio is saved only while "
                 + "Save sessions locally is on. Turning this off stops saving at once and keeps audio already saved.")
                .font(.caption).foregroundStyle(.secondary)
            if audio.enabled {
                Picker("Keep audio", selection: $audio.retentionDays) {
                    ForEach(SavedAudioPolicy.retentionChoices, id: \.self) { days in
                        Text(SavedAudioPolicy.retentionLabel(days)).tag(days)
                    }
                }
            }
            HStack {
                Text(SavedAudioPolicy.usageText(bytes: audio.bytesUsed, device: "this Mac"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Delete all saved audio…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(audio.bytesUsed == 0 || audio.runs.recorder.recordingConversation != nil)
            }
        }
        .onAppear { audio.applyRetention() }
        .confirmationDialog("Delete all saved audio?", isPresented: $confirmDeleteAll) {
            Button("Delete all saved audio", role: .destructive) { audio.deleteAll() }
        } message: { Text("Transcripts, notes and summaries are kept. This cannot be undone.") }
    }
}

/// History → a conversation's saved audio, with its lines that can seek (WhisperKit runs only).
struct MacSavedAudioSection: View {
    let record: SessionRecord
    @Bindable var audio = MacSavedAudio.shared

    private struct SeekableLine: Identifiable {
        let id: Int
        let segment: TranscriptSegment
        let target: SavedAudioSeek.Target
    }

    private var seekableLines: [SeekableLine] {
        (record.segments ?? []).enumerated().compactMap { index, segment in
            audio.playback.target(for: segment, index: index).map {
                SeekableLine(id: index, segment: segment, target: $0)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if audio.playback.hasAudio {
                SavedAudioPlayerView(playback: audio.playback)
                let lines = seekableLines
                if !lines.isEmpty {
                    DisclosureGroup("Play from a line (\(lines.count))") {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(lines) { line in
                                    Button {
                                        audio.playback.play(line.target)
                                    } label: {
                                        Text("\(SavedAudioPolicy.timeLabel(line.segment.start))  "
                                             + "\(line.segment.speakerLabel): \(line.segment.text)")
                                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.frame(maxHeight: 120)
                    }.font(.caption)
                } else {
                    Text("Lines recorded with Apple's speech engines have no times, "
                         + "so they cannot jump into the audio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: "\(record.id)-\(audio.revision)") { audio.playback.load(conversationID: record.id) }
        .onDisappear { audio.playback.load(conversationID: nil) }
    }
}
