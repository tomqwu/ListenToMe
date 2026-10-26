import SwiftUI
import AppKit
import ListenToMeCore

extension MeetingView {
    /// Replaces the old icon-row toolbar: Listen/Stop + pulsing indicator + elapsed timer on the
    /// left; the same icon actions that existed before on the right (refresh-models, import audio,
    /// export menu, copy-session, search, permissions, settings).
    func topControlBar(session: MeetingSession, showPermissions: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Button { toggleCapture(session: session) } label: {
                Label(wantsCapture || captureStartGate.isPending ? "Stop listening" : "Start listening",
                      systemImage: wantsCapture || captureStartGate.isPending ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Start or stop capturing microphone and system audio")
            .disabled(lifecycleBusy || isImporting || (!wantsCapture && !captureStartGate.isPending && !recordingAvailability.canRun))
            Button { saveConversation() } label: { Label("Save conversation", systemImage: "square.and.arrow.down") }
                .disabled(!hasConversation)
                .help("Save without stopping capture (Command-S)")
            Button { newConversation() } label: { Label("New conversation", systemImage: "plus") }
                .disabled(lifecycleBusy || isImporting)
                .help("Save this conversation, then start a clean one (Command-N)")
            Button { showSearch = true } label: { Label("History", systemImage: "clock") }
                .help("Open saved conversations (Command-F)")
            Menu {
                ConversationExportMenu(record: { currentRecord(date: conversationStartedAt ?? Date()) },
                                       hasTimestamps: TranscriptTimestamp.hasTimes(store.utterances),
                                       onError: { exportError = $0 }, onBegin: { exportError = nil })
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .help("Export or copy this conversation")
            Button { openSettings($showSettings) } label: { Label("Settings", systemImage: "gearshape") }
                .help("Configure transcription, AI, and saving (Command-comma)")
            Menu {
                Button("Re-transcribe saved audio…") { showRetranscription = true }
                    .disabled(!canRetranscribe)
                Button("Refresh models") { requestModelRefresh() }
                Button("Import audio or video…") { importAudioFile(session: session) }
                    .disabled(wantsCapture || lifecycleBusy || isImporting)
                Button("Permissions…") { showPermissions.wrappedValue = true }
                Button("Open-source licenses…") { showLicenses = true }
            } label: { Label("More", systemImage: "ellipsis") }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .controlSize(.large)
        .imageScale(.large)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.windowBackground)
    }

}
