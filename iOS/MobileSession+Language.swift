import Foundation
import ListenToMeCore

/// The transcription language, and Automatic mode (issue #197): detect the spoken language on this
/// device from the first stretch of speech, switch the live transcriber once if it differs, and
/// transcribe the recording so far again so the early wrong-language lines are replaced.
extension MobileSession {
    /// The picker tag for Automatic.
    static let automaticLanguageTag = "automatic"
    /// Extra transcription languages offered beside the device's own.
    static let offeredLanguages = ["en-US", "en-GB", "zh-CN", "zh-TW", "fr-FR", "de-DE", "ja-JP", "es-ES"]

    /// `Locale.current.identifier` is underscored ("en_US") while these tags are hyphenated, so a
    /// raw string comparison never matched and the picker listed the system language twice.
    static func selectableLanguages(system: Locale = .current) -> [String] {
        let current = Locale(identifier: system.identifier).identifier(.bcp47)
        return offeredLanguages.filter { Locale(identifier: $0).identifier(.bcp47) != current }
    }

    /// The language a new recording, or an Apple Watch recording, is transcribed in first. Automatic
    /// starts in the device's language; a switch applies only to the recording it happened in.
    var transcriptionLanguage: String { languageDetection.automatic ? Locale.current.identifier : language }

    /// The Settings picker's selection: Automatic, or a fixed language.
    var languageChoice: String {
        get { languageDetection.automatic ? Self.automaticLanguageTag : language }
        set {
            if newValue == Self.automaticLanguageTag {
                languageDetection.automatic = true
            } else {
                language = newValue
                languageDetection.automatic = false
            }
        }
    }

    /// Lines for Status details.
    var languageDiagnostics: String {
        let detection = languageDetection
        let mode = detection.automatic ? "Automatic (starts in \(Locale.current.identifier))" : "Fixed (\(language))"
        let model: String
        if case .unavailable(let reason) = detection.status {
            model = "unavailable: \(reason)"
        } else if !detection.hasModel {
            model = "not in this build"
        } else {
            model = detection.modelReady ? "ready on this device" : "not loaded in this app run"
        }
        return ["Transcription language: \(mode)",
                "Recording language: \(detection.run?.locale ?? "none")",
                "Language check: \(detection.lastResult ?? "not run")",
                "Language model: \(model)"].joined(separator: "\n")
    }

    /// Called for every speech event of a recording, in the recorder's own time. Starts the check once
    /// enough speech was heard; the check runs on its own task, so recording never waits for it.
    func noteLanguageSpeech(_ segment: TranscriptSegment) {
        guard let token = languageDetection.noteSpeech(start: segment.start, end: segment.end) else { return }
        languageDetection.check = Task { [weak self] in await self?.checkLanguage(token: token) }
    }

    /// Runs Whisper over the first window and switches when the policy says so.
    func checkLanguage(token: Int) async {
        let detection = languageDetection
        guard let model = detection.model, let samples = await detection.window(token: token),
              detection.isCurrent(token) else { return }
        let guess: LanguageGuess
        let supported: [String]
        do {
            try await model.prepare()   // joins the download or load the first speech started
            guard detection.isCurrent(token) else { return }
            detection.beginChecking()
            guess = try await model.detect(samples: samples)
            supported = await model.supportedLocales()
        } catch {
            detection.kept(nil, reason: error.localizedDescription, token: token)
            return
        }
        guard let run = detection.run, run.token == token, state == .recording else { return }
        let decision = LanguageDetectionPolicy.decide(
            detected: guess.language, probability: guess.probability, current: run.locale, supported: supported,
            pinned: !detection.automatic, alreadySwitched: run.switched, region: Locale.current.region?.identifier)
        switch decision {
        case .switchTo(let target): await switchLanguage(to: target, guess: guess, token: token)
        case .keep(let reason): detection.kept(guess, reason: Self.describe(reason), token: token)
        }
    }

    /// Restarts the live transcriber in `target`; it first hears the recording so far again, whose
    /// lines it replaces. On failure the recording keeps its language and a status line says why.
    private func switchLanguage(to target: String, guess: LanguageGuess, token: Int) async {
        let detection = languageDetection
        guard let recorder, let run = detection.run, run.token == token else { return }
        detection.beginSwitch(to: target)
        let conversation = id, from = run.locale, offset = run.offset, firstLine = run.firstLine
        var change: MobileLanguageDetection.Switch?
        do {
            try await recorder.switchLocale(to: Locale(identifier: target),
                                            replay: run.buffer) { [weak self] replayed, cut in
                guard let self else { return }
                change = MobileLanguageDetection.Switch(
                    detected: guess.language, from: from, to: target, conversation: conversation, firstLine: firstLine,
                    cut: offset + cut, originals: Array(self.segments.dropFirst(firstLine)))
                if replayed { self.removeRecordingLines(from: firstLine) }
            }
        } catch {
            detection.switchFailed(error.localizedDescription, guess: guess, to: target, token: token)
            return
        }
        if let change { detection.switched(change, guess: guess, token: token) }
    }

    /// Undo pins the language the recording started in, for this and later recordings. While the
    /// recording runs, transcription switches back, re-transcribing what it still holds; otherwise the
    /// lines the switch replaced come back.
    func undoLanguageSwitch() {
        let detection = languageDetection
        guard let change = detection.notice else { return }
        detection.clearNotice()
        language = change.from
        detection.automatic = false
        guard change.conversation == id else { return }
        guard state == .recording, let recorder, let run = detection.run else {
            restoreLines(change)
            return
        }
        let token = run.token
        Task { [weak self] in
            do {
                try await recorder.switchLocale(to: Locale(identifier: change.from),
                                                replay: run.buffer) { [weak self] replayed, _ in
                    if replayed {
                        self?.removeRecordingLines(from: change.firstLine)
                    } else {
                        self?.restoreLines(change)
                    }
                }
                self?.languageDetection.undone(to: change.from, token: token)
            } catch {
                self?.message = "Could not switch transcription back to " +
                    "\(MobileLanguageDetection.displayName(change.from)): \(error.localizedDescription)"
            }
        }
    }

    /// The new transcriber hears the whole recording again: its lines so far go, rather than being doubled.
    private func removeRecordingLines(from firstLine: Int) {
        speechCorrection.cancel()
        partial = nil
        guard firstLine < segments.count else { return }
        segments.removeSubrange(firstLine...)
        save(announce: false)
    }

    private func restoreLines(_ change: MobileLanguageDetection.Switch) {
        let restored = LanguageDetectionPolicy.restoring(change.originals, into: segments,
                                                         firstLine: change.firstLine, before: change.cut)
        guard restored != segments else { return }
        speechCorrection.cancel()
        segments = restored
        save(announce: false)
    }

    private static func describe(_ reason: LanguageDetectionPolicy.Reason) -> String {
        switch reason {
        case .pinned: return "fixed language"
        case .alreadySwitched: return "already switched"
        case .lowConfidence: return "not confident"
        case .sameLanguage: return "same language"
        case .unsupported: return "no on-device transcription for it"
        }
    }
}
