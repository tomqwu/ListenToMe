import SwiftUI
import AppKit
import ListenToMeCore

struct MacAIChoice: View {
    @Binding var selection: AIProcessingMode
    @State private var appleReason = AppleIntelligenceProvider.unavailableReason

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI processing")
                Menu(selection.label + (selection == .apple && appleReason != nil ? " · unavailable" : "")) {
                    ForEach(MacFeatureReadiness.selectableAIModes(appleReason: appleReason), id: \.self) { mode in
                        Button(mode.label) {
                            appleReason = AppleIntelligenceProvider.unavailableReason
                            selection = MacFeatureReadiness.selectAI(mode, current: selection, appleReason: appleReason)
                        }
                    }
                }
            }
            if let appleReason {
                Text(appleReason + " Choose a local model or explicitly configure another provider below. Recording is independent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { appleReason = AppleIntelligenceProvider.unavailableReason }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appleReason = AppleIntelligenceProvider.unavailableReason
        }
    }
}

struct MacEngineChoice: View {
    @Binding var selection: String
    @State private var availability: [String: FeatureAvailability] = [:]
    private let engines = ["speechAnalyzer", "speechRecognizer", "whisperKit"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transcription engine")
                Menu(TranscriptionEngineLabel.name(selection)) {
                    ForEach(engines.filter { availability[$0]?.canConfigure == true }, id: \.self) { engine in
                        Button(TranscriptionEngineLabel.name(engine)) { selection = engine }
                    }
                }
            }
            if let reason = availability[selection]?.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        let id = ProviderSettings.transcriptionLocaleID
        let locale = id.isEmpty ? Locale.current : Locale(identifier: id)
        var result: [String: FeatureAvailability] = [:]
        for engine in engines {
            result[engine] = await MacDeviceCapabilities.recording(engine: engine, locale: locale, checkMicrophone: false)
        }
        guard !Task.isCancelled else { return }
        availability = result
    }
}
