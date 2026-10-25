import SwiftUI
import AppKit
import ListenToMeCore

struct MacAIChoice: View {
    @Binding var selection: AIProcessingMode
    @State private var availability = MacAIAvailability()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI processing")
                Menu(selection.label + (selection == .apple && availability.reason != nil ? " · unavailable" : "")) {
                    ForEach(availability.choices, id: \.self) { mode in
                        Button(mode.label) {
                            selection = availability.select(mode, current: selection)
                        }
                    }
                }
            }
            if let appleReason = availability.reason {
                Text(appleReason + " Choose a local model or explicitly configure another provider below. Recording is independent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { availability.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            availability.refresh()
        }
    }
}

struct MacEngineChoice: View {
    @Binding var selection: String
    @AppStorage("transcriptionLocale") private var localeID = ""
    @State private var availability = MacEngineAvailability()
    private var locale: Locale { localeID.isEmpty ? .current : Locale(identifier: localeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transcription engine")
                Menu(TranscriptionEngineLabel.name(selection)) {
                    ForEach(availability.choices(for: locale), id: \.self) { engine in
                        Button(TranscriptionEngineLabel.name(engine)) {
                            selection = availability.select(engine, current: selection, locale: locale)
                        }
                    }
                }
            }
            if let reason = availability.status(for: selection, locale: locale).reason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: localeID) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        await availability.refresh(locale: locale)
    }
}
