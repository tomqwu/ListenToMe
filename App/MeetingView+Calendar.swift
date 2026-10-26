import Foundation
import ListenToMeCore

extension MeetingView {
    /// EventKit stays native; Core owns the asynchronous request and context/title policy.
    func loadFromCalendar(session: MeetingSession) {
        exportError = nil
        calendarContext.load(snapshot: {
            .init(conversationID: currentSessionID, notes: session.notes, title: conversationTitle,
                  titleState: conversationTitleState)
        }, lookup: { await CalendarService.currentOrNextMeeting() }, timeFormat: {
            $0.formatted(date: .omitted, time: .shortened)
        }, apply: { update in
            if let notes = update.notes { session.notes = notes }
            if let title = update.title, let state = update.titleState {
                conversationTitle = title; conversationTitleState = state
            }
            exportError = update.error
        })
    }
}
