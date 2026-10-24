import SwiftUI
import ListenToMeCore

/// Settings → Save audio recordings (issue #55). Off by default; explains where the audio stays and
/// what it costs, and offers automatic deletion and Delete all saved audio.
struct MobileSavedAudioSettings: View {
    @Bindable var savedAudio: MobileSavedAudio
    @State private var confirmDeleteAll = false

    var body: some View {
        Section {
            Toggle("Save audio recordings", isOn: $savedAudio.enabled)
                .accessibilityIdentifier("saveAudioToggle")
            if savedAudio.enabled {
                Picker("Keep audio", selection: $savedAudio.retentionDays) {
                    ForEach(SavedAudioPolicy.retentionChoices, id: \.self) { days in
                        Text(SavedAudioPolicy.retentionLabel(days)).tag(days)
                    }
                }.accessibilityIdentifier("savedAudioRetention")
            }
            Text(SavedAudioPolicy.usageText(bytes: savedAudio.bytesUsed))
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("savedAudioUsage")
            Button("Delete all saved audio…", role: .destructive) { confirmDeleteAll = true }
                .disabled(savedAudio.bytesUsed == 0)
                .accessibilityIdentifier("deleteAllSavedAudio")
        } header: { Text("Audio recordings") } footer: {
            Text("Off by default. When on, the microphone audio of each recording is saved with its conversation "
                 + "on this device, so you can play it back and share it. It is never uploaded, and it is always "
                 + "left out of iCloud and Finder backups. \(SavedAudioPolicy.estimateText()). Deleting a "
                 + "conversation deletes its audio. Apple Watch recordings keep no audio. Turning this off keeps "
                 + "audio already saved; delete it here.")
                .accessibilityIdentifier("savedAudioExplanation")
        }
        .confirmationDialog("Delete all saved audio?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all saved audio", role: .destructive) { savedAudio.deleteAll() }
        } message: {
            Text("Transcripts, notes and summaries are kept. This cannot be undone.")
        }
        .onAppear { savedAudio.applyRetention() }
    }
}

/// The main screen's line: audio is being saved, or why it is not.
struct MobileSavedAudioStatusLine: View {
    let session: MobileSession

    var body: some View {
        if let problem = session.savedAudio.problem {
            HStack(alignment: .firstTextBaseline) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption).lineLimit(3).foregroundStyle(.orange)
                Button("Dismiss") { session.savedAudio.dismissProblem() }
                    .font(.caption).buttonStyle(.borderless)
            }.accessibilityIdentifier("savedAudioProblem")
        } else if session.state == .recording, session.savedAudio.isSavingRun {
            Label("Saving audio on this device", systemImage: "waveform.badge.mic")
                .font(.caption).foregroundStyle(MobileStyle.muted)
                .accessibilityIdentifier("savedAudioRecording")
        }
    }
}

/// The open conversation's saved audio above its full transcript; tapping a line's time plays from it.
struct MobileSavedAudioTranscript: View {
    let session: MobileSession

    var body: some View {
        let playback = session.savedAudio.playback
        VStack(spacing: 0) {
            if session.canPlaySavedAudio {
                SavedAudioPlayerView(playback: playback).padding(16)
                Divider()
            }
            MobileTranscriptReader(segments: session.allSegments, scrollIdentifier: "expandedTranscriptScroll",
                                   restoreOriginal: session.restoreSpeech, showsSpeakers: session.hasSpeakerLabels,
                                   audioTarget: session.canPlaySavedAudio ? { segment in
                                       let index = session.allSegments.firstIndex { $0.id == segment.id } ?? 0
                                       return playback.target(for: segment, index: index)
                                   } : nil,
                                   playAudio: { playback.play($0) }, addTerm: session.addToMyTerms)
                .id(session.id)
        }
        .task(id: "\(session.id)-\(session.savedAudio.revision)-\(session.state == .idle)") {
            playback.load(conversationID: session.state == .idle ? session.id : nil)
        }
        .onDisappear { playback.stop() }
    }
}
