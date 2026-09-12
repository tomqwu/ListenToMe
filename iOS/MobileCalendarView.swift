import SwiftUI

struct MobileCalendarView: View {
    @Bindable var session: MobileSession
    @State private var calendar = MobileCalendar()
    @State private var day = Date()
    @State private var selected: MobileCalendarEvent?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose an event to copy its details into this conversation's notes. " +
                         "Imported notes are included when you use AI summaries, including Auto summary.")
                    Text("Calendar events are not changed.").font(.caption).foregroundStyle(.secondary)
                }
                if calendar.access == .ready {
                    Section {
                        DatePicker("Event date", selection: $day, displayedComponents: .date)
                            .accessibilityIdentifier("calendarDate").disabled(calendar.loading)
                        Button("Refresh events") { Task { await calendar.load(day: day) } }
                            .disabled(calendar.loading)
                    }
                    Section("Events") {
                        if calendar.loading { ProgressView("Loading events…") }
                        if calendar.events.isEmpty && !calendar.loading && calendar.message == nil {
                            Text("No events on this date. Choose another date or check the calendars set up on this device.")
                                .accessibilityIdentifier("calendarEmpty")
                        }
                        ForEach(calendar.events) { event in
                            Button { selected = event } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.meeting.title).foregroundStyle(.primary)
                                    Text(event.allDay ? "All day" : (event.meeting.start?.formatted(date: .omitted,
                                         time: .shortened) ?? ""))
                                        .font(.caption)
                                    Text(event.calendarName).font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("calendar-event-\(event.meeting.title)")
                        }
                    }
                } else {
                    Section {
                        if calendar.access == .notRequested {
                            Button("Connect Calendar") { Task { await calendar.load(day: day, requestAccess: true) } }
                                .disabled(calendar.loading).accessibilityIdentifier("connectCalendar")
                        } else {
                            Text(calendar.access == .restricted
                                 ? "Calendar access is restricted on this device."
                                 : "Allow full Calendar access in Settings to read existing events.")
                                .accessibilityIdentifier("calendarAccessReason")
                            if calendar.access == .denied {
                                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                            }
                        }
                    }
                }
                if let message = calendar.message { Section { Text(message) } }
            }
            .accessibilityIdentifier("calendarImportList")
            .navigationTitle("Import from Calendar")
            .toolbar { Button("Done") { dismiss() } }
            .task(id: day) { await calendar.load(day: day) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await calendar.load(day: day) } }
            }
            .sheet(item: $selected) { event in
                NavigationStack {
                    ScrollView {
                        Text(event.context).frame(maxWidth: .infinity, alignment: .leading).padding()
                            .accessibilityIdentifier("calendarEventPreview")
                        if let message = session.message { Text(message).font(.caption).padding(.horizontal) }
                    }
                    .navigationTitle("Event details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selected = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Import") {
                                if session.importCalendarEvent(event) { selected = nil; dismiss() }
                            }.disabled(session.isSummarizing).accessibilityIdentifier("importCalendarEvent")
                        }
                    }
                }
            }
        }
    }
}
