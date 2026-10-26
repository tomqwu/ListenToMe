import SwiftUI
import ListenToMeCore

/// Settings → Speakers: the switch (on unless turned off), what it costs, and where the models stand
/// (issues #180, #195).
struct MobileSpeakerSettings: View {
    let session: MobileSession
    @Bindable var speakers: MobileSpeakers

    init(session: MobileSession) {
        self.session = session
        speakers = session.speakers
    }

    var body: some View {
        Section {
            Toggle("Identify speakers", isOn: $speakers.enabled)
                .disabled(session.state != .idle && !speakers.enabled)
                .accessibilityIdentifier("identifySpeakersToggle")
            Text("Labels transcript lines Speaker 1, Speaker 2… so you can rename them in Notes. Runs on this "
                 + "device; audio is never sent and is kept only when Save audio recordings is on. "
                 + "While this is on, speaker models download once from "
                 + "huggingface.co, before your first recording needs them. Uses more battery while listening.")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("identifySpeakersExplanation")
            if speakers.enabled { MobileSpeakerModelRow(session: session) }
        } header: { Text("Speakers") } footer: {
            Text("You can turn labels off while listening; turn them on again after Stop. "
                 + "Labels are estimates: similar voices can merge in group conversations, and overlapping speech "
                 + "or very short phrases may stay Microphone. Voices are not recognized across recordings.")
        }
    }
}

/// Notes → Speakers: rename the speakers named on this conversation's transcript.
struct MobileSpeakerList: View {
    @Bindable var session: MobileSession

    var body: some View {
        Section("Speakers") {
            if session.speakerList.isEmpty {
                Text(session.speakers.enabled
                     ? "Labels appear about 20 seconds into a recording, and at Stop once the models are ready."
                     : "Turn on Identify speakers in Settings to label who said what.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(session.speakerList) { speaker in
                    MobileSpeakerNameField(speaker: speaker) { session.renameSpeaker(id: speaker.id, to: $0) }
                }
                Text("Renaming updates every line, History search and exports. Summaries pick up the new names "
                     + "the next time they are generated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MobileSpeakerNameField: View {
    let speaker: MobileSession.SpeakerEntry
    let rename: (String) -> Void
    @State private var name = ""
    @FocusState private var editing: Bool

    var body: some View {
        LabeledContent {
            Text(speaker.lines == 1 ? "1 line" : "\(speaker.lines) lines")
                .font(.caption).foregroundStyle(.secondary)
        } label: {
            TextField("Speaker name", text: $name)
                .focused($editing)
                .submitLabel(.done)
                .onSubmit { commit() }
                .accessibilityLabel("Name for \(speaker.name)")
                .accessibilityIdentifier("speakerName-\(speaker.id)")
        }
        .onAppear { name = speaker.name }
        .onChange(of: speaker.name) { _, newName in if !editing { name = newName } }
        .onChange(of: editing) { _, isEditing in if !isEditing { commit() } }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == speaker.name { name = speaker.name; return }
        rename(trimmed)
    }
}

/// The recording screen's line about speaker labels (#195), under the title status, with Retry when the
/// models failed or are not loaded. Shown only while it has news (`statusLineIsShown`); the steady
/// states read "Speaker labels on" in the status above, so the workspace keeps its height.
struct MobileSpeakerStatus: View {
    let session: MobileSession

    var body: some View {
        if session.speakers.statusLineIsShown, let line = session.speakers.statusLine {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(line, systemImage: session.speakers.isUnavailable ? "person.2.slash" : "person.2.wave.2")
                    .font(.caption).foregroundStyle(MobileStyle.muted).lineLimit(3)
                    .accessibilityIdentifier("speakerStatus")
                if session.speakers.showsRetry {
                    Button("Retry") { session.retrySpeakerIdentification() }
                        .font(.caption.weight(.semibold)).buttonStyle(.borderless)
                        .accessibilityIdentifier("retrySpeakers")
                }
            }
        }
    }
}

/// Settings → Speakers: the models' download progress, ready state, or failure with Retry (#195).
private struct MobileSpeakerModelRow: View {
    let session: MobileSession

    var body: some View {
        let speakers = session.speakers
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if speakers.modelsReady {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            } else if speakers.isUnavailable || speakers.showsRetry {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(speakers.modelLine).font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("speakerModelState")
            if speakers.showsRetry {
                Button("Retry") { session.retrySpeakerIdentification() }
                    .font(.footnote.weight(.semibold)).buttonStyle(.borderless)
                    .accessibilityIdentifier("retrySpeakerModels")
            }
        }
    }
}
