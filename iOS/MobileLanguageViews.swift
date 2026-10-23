import SwiftUI

/// Settings → Transcription: Automatic (default) or a fixed language (issue #197).
struct MobileLanguageSettings: View {
    @Bindable var session: MobileSession

    var body: some View {
        Section("Transcription") {
            Picker("Language", selection: $session.languageChoice) {
                Text("Automatic (default)").tag(MobileSession.automaticLanguageTag)
                Text("System (\(Locale.current.identifier))").tag(Locale.current.identifier)
                ForEach(MobileSession.selectableLanguages(), id: \.self) { locale in
                    Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale)
                }
            }.disabled(session.busy).accessibilityIdentifier("transcriptionLanguage")
            if session.languageDetection.automatic {
                Text("Automatic starts in this device's language and listens to the first few seconds of speech. " +
                     "If you speak another language, it switches once and transcribes the recording again. " +
                     "Detection runs on this device; its model (\(WhisperLanguageIdentifier.downloadDescription)) " +
                     "downloads once from huggingface.co. Audio is never uploaded.")
                    .font(.caption).accessibilityIdentifier("automaticLanguageExplanation")
            }
            Text("Speech models may download on first use. Audio is transcribed on your device and is not saved.")
        }
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
                    .font(.caption.weight(.semibold)).accessibilityIdentifier("undoLanguageSwitch")
                    .accessibilityHint("Pins the language the recording started in")
            }
        } else if let line = detection.statusLine {
            Label(line, systemImage: "globe").font(.caption).lineLimit(3).foregroundStyle(.secondary)
                .accessibilityIdentifier("languageStatus")
        }
    }
}
