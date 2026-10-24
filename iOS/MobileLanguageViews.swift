import ListenToMeCore
import SwiftUI

/// Settings → Transcription: Automatic (default) or a fixed language (issue #197), from every language
/// this iPhone can transcribe, installed ones first (issue #172).
struct MobileLanguageSettings: View {
    @Bindable var session: MobileSession

    var body: some View {
        Section("Transcription") {
            let groups = Self.languageGroups(selected: session.languageDetection.automatic ? nil : session.language)
            Picker("Language", selection: $session.languageChoice) {
                Text("Automatic (default)").tag(MobileSession.automaticLanguageTag)
                Text("System (\(Locale.current.identifier))").tag(Locale.current.identifier)
                languageSection("Installed", groups.installed)
                languageSection("Downloadable", groups.downloadable)
            }.disabled(session.busy).accessibilityIdentifier("transcriptionLanguage")
                .task { await SpeechLanguageCatalog.shared.load() }   // refreshes which models are installed
            if session.languageDetection.automatic {
                Text("Automatic starts in this device's language and listens to the first few seconds of speech. " +
                     "If you speak another language, it switches and transcribes the recording again. It checks " +
                     "again about once a minute while people talk, so a later change of language switches too. " +
                     "Detection runs on this device; its model (\(WhisperLanguageIdentifier.downloadDescription)) " +
                     "downloads once from huggingface.co. Audio is never uploaded.")
                    .font(.caption).accessibilityIdentifier("automaticLanguageExplanation")
            }
            Text("Speech models may download on first use. Audio is transcribed on your device and is never sent. "
                 + "Audio is kept only when Save audio recordings is on.")
        }
    }

    @ViewBuilder private func languageSection(_ title: String, _ locales: [String]) -> some View {
        if !locales.isEmpty {
            Section(title) {
                ForEach(locales, id: \.self) { locale in Text(Self.label(locale)).tag(locale) }
            }
        }
    }

    static func label(_ locale: String) -> String { Locale.current.localizedString(forIdentifier: locale) ?? locale }

    /// The fixed languages offered below Automatic and System: every language on-device transcription
    /// supports (or the common ones where the list is unavailable), without the system language, which
    /// has its own entry. `selected` is the stored fixed language, kept even if no longer listed.
    @MainActor
    static func languageGroups(system: Locale = .current, selected: String?,
                               catalog: SpeechLanguageCatalog = .shared) -> TranscriptionLanguageGroups {
        catalog.groups(excluding: [system.identifier], selected: selected, label: label)
    }
}

/// The language line in the meeting status area: the check in progress, why it paused, or the
/// notice after a switch with its Undo.
struct MobileLanguageStatus: View {
    let session: MobileSession

    var body: some View {
        let detection = session.languageDetection
        // The notice belongs to the conversation that switched; another one opened since shows none.
        if detection.notice?.conversation == session.id, let notice = detection.noticeText {
            HStack(spacing: 8) {
                Label(notice, systemImage: "globe").font(.caption.weight(.medium))
                    .foregroundStyle(MobileStyle.accent).accessibilityIdentifier("languageNotice")
                Button("Undo") { session.undoLanguageSwitch() }
                    .disabled(!session.canUndoLanguageSwitch)
                    .font(.caption.weight(.semibold)).accessibilityIdentifier("undoLanguageSwitch")
                    .accessibilityHint("Pins the language the recording started in")
            }
        } else if let line = detection.statusLine {
            Label(line, systemImage: "globe").font(.caption).lineLimit(3).foregroundStyle(.secondary)
                .accessibilityIdentifier("languageStatus")
        }
    }
}
