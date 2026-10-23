import SwiftUI
import ListenToMeCore

/// Settings → Speakers: the opt-in switch and what it costs (issue #180).
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
                .disabled(session.state != .idle)
                .accessibilityIdentifier("identifySpeakersToggle")
            Text("Labels transcript lines Speaker 1, Speaker 2… so you can rename them in Notes. Runs on this "
                 + "device; audio is not saved or sent. The first time, speaker models download from "
                 + "huggingface.co. Uses more battery while listening.")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("identifySpeakersExplanation")
        } header: { Text("Speakers") } footer: {
            Text("Labels are estimates: overlapping speech and very short phrases are often left as Microphone, "
                 + "and a voice is not recognized again after you stop and start listening.")
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
                     ? "Speaker labels appear about 20 seconds into a recording and are finished when you stop."
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

/// The meeting status area's line about speaker identification, with Retry after a model failure.
struct MobileSpeakerStatus: View {
    let session: MobileSession

    var body: some View {
        if session.speakers.enabled, let line = session.speakers.statusLine {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(line, systemImage: session.speakers.isUnavailable ? "person.2.slash" : "person.2.wave.2")
                    .font(.caption).foregroundStyle(MobileStyle.muted).lineLimit(3)
                    .accessibilityIdentifier("speakerStatus")
                if session.speakers.isUnavailable {
                    Button("Retry") { session.retrySpeakerIdentification() }
                        .font(.caption.weight(.semibold)).buttonStyle(.borderless)
                        .accessibilityIdentifier("retrySpeakers")
                }
            }
        }
    }
}
