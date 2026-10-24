import AVFoundation
import SwiftUI
import ListenToMeCore

/// Plays a conversation's saved audio (issue #55): one part at a time, with seeking from transcript lines
/// whose times match the audio. Local files only; nothing is streamed or uploaded.
@MainActor @Observable
final class SavedAudioPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var conversationID: String?
    private(set) var runs: [SavedAudioRun] = []
    private(set) var selected: SavedAudioRun?
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var problem: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored let library: SavedAudioLibrary

    init(library: SavedAudioLibrary) {
        self.library = library
    }

    var hasAudio: Bool { !runs.isEmpty }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var fileURLs: [URL] {
        guard let conversationID else { return [] }
        return runs.compactMap { library.url(for: $0, conversationID: conversationID) }
    }

    /// Reads the conversation's parts again. Keeps the part and position when they still exist.
    func load(conversationID id: String?) {
        let fresh = id.map(library.runs(for:)) ?? []
        if id != conversationID {
            stop()
            player = nil; selected = nil; duration = 0; problem = nil
            conversationID = id
            runs = fresh
            select(fresh.first)
            return
        }
        guard fresh != runs else { return }
        runs = fresh
        if let selected, let same = fresh.first(where: { $0.fileName == selected.fileName }) {
            // A part that finished saving after it was opened is opened again, now complete.
            let finishedSince = same.duration != selected.duration && !isPlaying
            self.selected = same
            if finishedSince { player = nil; select(same) }
        } else {
            select(fresh.first)
        }
    }

    func select(_ run: SavedAudioRun?) {
        guard run?.fileName != selected?.fileName || player == nil else { return }
        stop()
        selected = run
        player = nil
        duration = 0
        problem = nil
        guard let run, let id = conversationID, let url = library.url(for: run, conversationID: id) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            problem = "This part cannot be played. The app may have closed before it finished saving."
        }
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard let player else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        isPlaying = player.play()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Stops playback, for example when recording starts or the conversation changes.
    func stop() {
        guard player != nil || isPlaying else { return }
        player?.stop()
        if isPlaying {
            isPlaying = false
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = min(max(0, time), duration)
    }

    /// Where the line at `index` plays from, or `nil` when it cannot seek.
    func target(for segment: TranscriptSegment, index: Int) -> SavedAudioSeek.Target? {
        SavedAudioSeek.target(for: segment, index: index, in: runs)
    }

    /// Plays the line's part from its time.
    func play(_ target: SavedAudioSeek.Target) {
        select(target.run)
        seek(to: target.time)
        play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}

/// A compact player: part picker, play/pause, position, and Share audio for the share sheet.
struct SavedAudioPlayerView: View {
    let playback: SavedAudioPlayback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Saved audio", systemImage: "waveform").font(.subheadline.weight(.semibold))
                Spacer()
                ShareLink(items: playback.fileURLs) {
                    Label("Share audio", systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("shareSavedAudio")
            }
            if playback.runs.count > 1 {
                Picker("Part", selection: Binding(get: { playback.selected?.fileName ?? "" }, set: { name in
                    playback.select(playback.runs.first { $0.fileName == name })
                })) {
                    ForEach(playback.runs) { run in
                        Text(run.title(partCount: Set(playback.runs.map(\.index)).count)).tag(run.fileName)
                    }
                }.accessibilityIdentifier("savedAudioPart")
            }
            HStack(spacing: 12) {
                Button(playback.isPlaying ? "Pause" : "Play",
                       systemImage: playback.isPlaying ? "pause.fill" : "play.fill") { playback.togglePlay() }
                    .labelStyle(.iconOnly).font(.title3).frame(minWidth: 44, minHeight: 44)
                    .disabled(playback.duration <= 0)
                    .accessibilityIdentifier("savedAudioPlay")
                TimelineView(.animation(minimumInterval: 0.5, paused: !playback.isPlaying)) { _ in
                    HStack(spacing: 8) {
                        Slider(value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                               in: 0...max(1, playback.duration))
                            .accessibilityLabel("Playback position")
                            .accessibilityValue(SavedAudioPolicy.timeLabel(playback.currentTime))
                        Text("\(SavedAudioPolicy.timeLabel(playback.currentTime)) / "
                             + SavedAudioPolicy.timeLabel(playback.duration))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let problem = playback.problem ?? playback.selected?.failure {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("savedAudioPlayer")
    }
}
