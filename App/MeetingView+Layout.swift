import SwiftUI
import ListenToMeCore

extension MeetingView {
    var workspaceContent: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            topControlBar(session: session, showPermissions: $showPermissions)
            conversationStatus
            if !wantsCapture, let reason = recordingAvailability.reason {
                HStack {
                    Text(reason).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Settings") { openSettings($showSettings) }
                    Button("Permissions") { showPermissions = true }
                }.padding(.horizontal, 14).padding(.vertical, 6)
            }
            if !modelStatus.isEmpty && ProviderSettings.aiMode != .off {
                VStack(alignment: .leading, spacing: 6) {
                    Text(modelStatus).font(.callout).foregroundStyle(.orange)
                    if ProviderSettings.aiMode == .local, let readiness = localOllamaReadiness {
                        LocalOllamaHelp(readiness: readiness) { requestModelRefresh() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
            }
            if let startError {
                MeetingErrorBanner(message: startError, dismissLabel: "Dismiss capture message",
                                   dismiss: { self.startError = nil }, openSettings: permissions.openSettings)
            }
            if let exportError {
                MeetingErrorBanner(message: exportError, dismissLabel: "Dismiss file or calendar message",
                                   dismiss: { self.exportError = nil }, openSettings: permissions.openSettings)
            }
            calendarSuggestionBanner
            MacVocabularyBanner(vocabulary: vocabulary, conversationID: currentSessionID, apply: applyVocabulary)
            // HSplitView so the user can drag the rail/transcript/copilot dividers; each column
            // carries its own min/ideal/max width so the handles have room to move.
            HSplitView {
                statusRail(session: session)
                transcriptColumn(session: session, notes: $session.notes)
                copilotColumn(session: session)
            }
            .frame(maxHeight: .infinity)
            CommandCenterFooter(mode: ProviderSettings.aiMode)
        }
    }
}
