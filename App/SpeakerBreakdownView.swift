import SwiftUI
import ListenToMeCore

struct SpeakerBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    let loading: Bool
    let participants: [SpeakerParticipant]
    let errorText: String?
    let didTruncate: Bool
    let perLineLabelsUnavailable: Bool
    let onRename: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Speakers").font(.title2).bold()
            if loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Analyzing voices… First use downloads models.").font(.caption)
                }
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if participants.isEmpty && !loading {
                Text("Capture a few seconds of speech. Speakers update automatically while listening and after Stop.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(participants) { speaker in
                        SpeakerNameRow(speaker: speaker, onRename: onRename)
                    }
                }
            }
            .frame(maxHeight: 300)
            if didTruncate {
                Text("Only the first ~2 hours of each channel are analyzed.").font(.caption)
            }
            if perLineLabelsUnavailable {
                Text("Choose WhisperKit in Settings before Listen to include speaker names in transcript lines, " +
                     "AI answers, and exports. This engine supports the voice breakdown only.")
                    .font(.caption)
            }
            Text("On-device · Labels may be revised as more audio arrives. Names apply to this recording run. " +
                 "Microphone and system voices are grouped separately; overlapping speech can be misattributed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private struct SpeakerNameRow: View {
    let speaker: SpeakerParticipant
    let onRename: (String, String) -> Void
    @State private var name: String

    init(speaker: SpeakerParticipant, onRename: @escaping (String, String) -> Void) {
        self.speaker = speaker
        self.onRename = onRename
        _name = State(initialValue: speaker.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Speaker name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                    .accessibilityLabel("Name for \(speaker.name)")
                Button("Save name") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == speaker.name)
            }
            Text("\(speaker.source == .you ? "Microphone" : "System audio") · " +
                 "\(Int(speaker.seconds.rounded())) seconds of speech")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: speaker.name) { _, updated in name = updated }
    }

    private func save() {
        onRename(speaker.id, name)
    }
}
