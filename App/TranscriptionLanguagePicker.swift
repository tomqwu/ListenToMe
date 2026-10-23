import ListenToMeCore
import SwiftUI

/// The status rail's transcription-language picker: Auto (system), then every language this Mac can
/// transcribe on the device, installed models first and downloadable ones after (issue #172). The
/// options come from `SpeechLanguageCatalog`; their order and grouping from Core's
/// `TranscriptionLanguageCatalog`. Apple's on-device Speech transcribes one primary language; it does
/// not auto-detect or code-switch (the opt-in WhisperKit engine does, with Auto).
struct TranscriptionLanguagePicker: View {
    /// A BCP 47 locale id; "" follows the system language ("Auto").
    let selection: Binding<String>

    /// Hand-written names for the common languages; the rest use the system's name for the locale.
    static let labels: [String: String] = [
        "en-US": "English (US)",
        "zh-CN": "中文 · Mandarin (简体)",
        "zh-TW": "中文 · Mandarin (繁體)",
        "yue-CN": "粵語 · Cantonese",
        "ja-JP": "日本語",
        "ko-KR": "한국어",
        "es-ES": "Español",
        "fr-FR": "Français",
        "de-DE": "Deutsch",
    ]

    static func label(_ id: String) -> String {
        labels[id] ?? Locale.current.localizedString(forIdentifier: id) ?? id
    }

    var body: some View {
        let languages = SpeechLanguageCatalog.shared.groups(selected: selection.wrappedValue, label: Self.label)
        Picker("Language", selection: selection) {
            Text("Auto (system)").tag("")
            section("Installed", languages.installed)
            section("Downloadable", languages.downloadable)
        }
        .labelsHidden().controlSize(.small)
        .help("Transcription language — applies the next time you press Start listening. "
              + "A downloadable language's speech model downloads when you start.")
        .task { await SpeechLanguageCatalog.shared.load() }   // refreshes which models are installed
    }

    @ViewBuilder private func section(_ title: String, _ ids: [String]) -> some View {
        if !ids.isEmpty {
            Section(title) { ForEach(ids, id: \.self) { Text(Self.label($0)).tag($0) } }
        }
    }
}
