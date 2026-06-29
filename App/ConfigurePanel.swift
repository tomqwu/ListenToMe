import SwiftUI
import ListenToMeCore

// MARK: - Configure popover
//
// The slim cockpit top bar keeps only Listen + timer + preset visible; everything that used to live
// in the left status rail (language, proactive, per-role models, references, calendar, identify
// speakers, session stats) is one ⚙ click away here. Reuses the same `railSection`/`modelPicker`
// helpers as the old rail so behavior (and the onChange side effects in the bindings) is identical.

extension MeetingView {
    func configurePopover(session: MeetingSession) -> some View {
        @Bindable var session = session
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                railSection("Engine") {
                    Text(CommandCenterLabels.engine(ProviderSettings.transcriptionEngine))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                    Picker("Language", selection: languageBinding(session: session)) {
                        ForEach(Self.languageOptions, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden().controlSize(.small)
                    .help("Transcription language — applies the next time you press Listen")
                }

                railSection("Proactive") {
                    Toggle("Proactive replies", isOn: $session.proactiveEnabled)
                        .controlSize(.small).labelsHidden()
                        .toggleStyle(.switch)
                        .help("Let Quick/Listener react automatically as the conversation flows")
                }

                railSection("Models") {
                    ForEach(CopilotRole.allCases, id: \.self) { role in
                        modelPicker(role: role, session: session, label: railRoleName(role))
                    }
                }

                railSection("References") {
                    Button { loadFromCalendar(session: session) } label: {
                        Label("Load from Calendar", systemImage: "calendar")
                    }
                    .controlSize(.small)
                    .help("Fill Context notes from your current or next calendar meeting")
                    referenceFilesRow(session: session)
                }

                if ProviderSettings.speakerDiarizationEnabled { speakersRailSection() }

                railSection("Session") {
                    StatRow(key: "turns", value: "\(store.utterances.count)")
                    StatRow(key: "you / others", value: "\(youCount) / \(othersCount)")
                    StatRow(key: "~tok", value: "\(approxTokens)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 320, height: 440)
    }
}
