import SwiftUI
import EventKit
import ListenToMeCore

extension MeetingView {
    private var canSuggestMeeting: Bool {
        UserDefaults.standard.bool(forKey: "suggestCalendarMeetings") && !showSettings
            && !showSearch && !wantsCapture && !session.isRunning && !lifecycleBusy
            && !session.isTranscribingFile && !importWork.isActive && !hasConversation
            && restoredRecord == nil && lastSavedKey == nil && conversationTitleState == .placeholder
    }

    @ViewBuilder var calendarSuggestionBanner: some View {
        if let meeting = suggestedMeeting, canSuggestMeeting {
            HStack {
                Image(systemName: "calendar")
                Text("Happening now: \(meeting.title)").lineLimit(1)
                Spacer()
                Button("Use context and Start") {
                    guard canSuggestMeeting,
                          meetingSuggestionPolicy.suggestion(from: .meeting(meeting), enabled: true,
                                                             idleAndEmpty: true, now: Date()) != nil else { return }
                    session.notes = MeetingContext.notes(for: meeting) {
                        $0.formatted(date: .omitted, time: .shortened)
                    }
                    conversationTitle = meeting.title
                    conversationTitleState = .calendar
                    meetingSuggestionPolicy.dismiss(meeting, now: Date())
                    suggestedMeeting = nil
                    toggleCapture(session: session)
                }
                Button("Dismiss") {
                    meetingSuggestionPolicy.dismiss(meeting, now: Date())
                    suggestedMeeting = nil
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .help("Adds this event to Context and starts listening using your current AI settings.")
        }
    }

    func pollMeetingSuggestion(now: Date) {
        guard canSuggestMeeting else { suggestedMeeting = nil; return }
        if let meeting = suggestedMeeting, (meeting.end ?? .distantPast) <= now { suggestedMeeting = nil }
        guard now >= nextMeetingPoll else { return }
        nextMeetingPoll = now.addingTimeInterval(30)
        let conversationID = currentSessionID
        calendarSuggestionWork.start(load: {
            await CalendarService.currentOrNextMeeting(now: now, requestAccess: false)
        }, apply: { lookup in
            guard canSuggestMeeting, currentSessionID == conversationID else { return }
            suggestedMeeting = meetingSuggestionPolicy.suggestion(from: lookup, enabled: true,
                                                                  idleAndEmpty: true, now: Date())
        })
    }
}

struct CalendarSuggestionSettings: View {
    @Binding var enabled: Bool
    @State private var accessStatus: String?
    @State private var accessWork = LatestResultCoordinator<CalendarLookup>()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Suggest current calendar meetings", isOn: $enabled)
            Text("Off by default. In a new, empty conversation, offer a current event every 30 seconds. " +
                 "Only Use context and Start begins recording. Calendar context follows your AI processing settings.")
                .font(.caption).foregroundStyle(.secondary)
            if enabled {
                Button("Allow Calendar access") {
                    accessWork.start(load: { await CalendarService.currentOrNextMeeting() }, apply: { result in
                        accessStatus = result.offersPrivacySettings
                            ? "Calendar access is denied. Enable ListenToMe in System Settings → Privacy & Security → Calendars."
                            : (EKEventStore.authorizationStatus(for: .event) == .fullAccess
                               ? "Calendar access is enabled." : result.message)
                    })
                }
                if let accessStatus { Text(accessStatus).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onDisappear { accessWork.cancel() }
        .onChange(of: enabled) { _, isEnabled in if !isEnabled { accessWork.cancel() } }
    }
}
