import Foundation
import ListenToMeCore

/// The transcription language, and Automatic mode (issue #197): detect the spoken language on this
/// device from the first stretch of speech, switch the live transcriber once if it differs, and
/// transcribe the recording so far again so the early wrong-language lines are replaced.
extension MobileSession {
    /// The picker tag for Automatic.
    static let automaticLanguageTag = "automatic"
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

    /// The language this recording is transcribed in: the device's or the fixed one, or the language a
    /// conversation switched to, which a resumed recording keeps.
    var recordingLanguage: String { languageDetection.run?.locale ?? transcriptionLanguage }

    /// The language the open conversation is in, for checks such as Apple Intelligence's: the switched-to
    /// language once detection switched it, else the recording's.
    var conversationLanguage: String {
        if let notice = languageDetection.notice, notice.conversation == id { return notice.to }
        return recordingLanguage
    }

    /// Called for every result of a recording, in the recorder's own time, before it reaches the
    /// transcript. Notes the speech for the language check, and returns true when a replay holds the
    /// result back (see `MobileLanguageDetection.Replay`), so the caller must not add it.
    func stageLanguageSegment(_ segment: TranscriptSegment, offset: TimeInterval) -> Bool {
        noteLanguageSpeech(segment)
        guard let replay = languageDetection.replay else { return false }
        guard offset + segment.start < replay.cut else {
            // Live speech after the switch: the replay has caught up. A discarded replay keeps
            // filtering, because the transcriber it belonged to may still be finishing.
            if !replay.discarded { commitReplay(complete: true) }
            return false
        }
        guard !replay.discarded else { return true }
        if segment.isFinal {
            languageDetection.replay?.lines.append(TranscriptSegment(
                source: .you, text: segment.text, isFinal: true, start: offset + segment.start,
                end: offset + segment.end, speakerName: Self.microphoneLabel))
        }
        return true
    }

    /// Ends the language side of a recording, after the recorder has delivered its last result: a replay
    /// still held is committed as far as it got, the recording's lines are noted for Undo, and an Undo
    /// tapped while stopping is applied.
    func endLanguageRun() {
        if languageDetection.replay?.discarded == false { commitReplay(complete: false) }
        let lines = languageDetection.run.map { run in
            Set(segments.dropFirst(run.firstLine).filter { !Self.isWatchLine($0) }.map(\.id))
        }
        languageDetection.endRun(recordingLines: lines)
        if languageDetection.pendingUndo, state == .idle, let change = languageDetection.notice {
            finishUndo(change)
        }
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
        guard let model = detection.model, detection.isCurrent(token) else { return }
        guard let samples = await detection.window(token: token) else {
            detection.kept(nil, reason: "no speech in the first two minutes", token: token)
            return
        }
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
    /// lines it replaces once it has caught up. On failure the recording keeps its language and a
    /// status line says why.
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
                if replayed { self.beginReplay(token: token, firstLine: firstLine, cut: offset + cut) }
                change = MobileLanguageDetection.Switch(
                    detected: guess.language, from: from, to: target, conversation: conversation, runToken: token,
                    firstLine: firstLine, cut: offset + cut, originals: Array(self.segments.dropFirst(firstLine)),
                    replayed: replayed)
            }
        } catch {
            detection.switchFailed(error.localizedDescription, guess: guess, to: target, token: token)
            return
        }
        if let change { detection.switched(change, guess: guess, token: token) }
    }

    /// The new transcriber hears the recording again. Its lines are held until it catches up, while the
    /// current lines stay on screen and on disk. The unfinished line becomes a line of its own, so an
    /// Undo can bring it back.
    private func beginReplay(token: Int, firstLine: Int, cut: TimeInterval) {
        speechCorrection.cancel()
        if let partial { segments.append(partial); self.partial = nil }
        languageDetection.replay = .init(token: token, firstLine: firstLine, cut: cut)
    }

    /// Puts the held replay lines in place of the recording's earlier lines, in one step.
    private func commitReplay(complete: Bool) {
        guard let replay = languageDetection.replay else { return }
        languageDetection.replay = nil
        guard replay.firstLine <= segments.count else { return }
        let merged = LanguageDetectionPolicy.mergingReplay(replay.lines, over: Array(segments[replay.firstLine...]),
                                                           complete: complete)
        speechCorrection.cancel()
        segments = Array(segments[..<replay.firstLine]) + merged
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

/// Undo of a language switch (issue #197).
extension MobileSession {
    /// Undo is offered for the open conversation's switch, except while a recording is starting or an
    /// Undo is already switching back. While stopping, a tap is kept and applied once Stop finishes.
    var canUndoLanguageSwitch: Bool {
        languageDetection.notice?.conversation == id && !languageDetection.undoing && state != .preparing
    }

    /// Undo pins the language the recording started in, for this and later recordings. While recording,
    /// transcription switches back first, and the notice stays until that has worked; once stopped, the
    /// lines the switch replaced come back.
    func undoLanguageSwitch() {
        guard let change = languageDetection.notice, !languageDetection.undoing else { return }
        guard change.conversation == id else { pin(change); return }
        switch state {
        case .preparing: return
        case .stopping: languageDetection.pendingUndo = true
        case .idle: finishUndo(change)
        case .recording: undoWhileRecording(change)
        }
    }

    private func undoWhileRecording(_ change: MobileLanguageDetection.Switch) {
        guard let recorder, let run = languageDetection.run else { return finishUndo(change) }
        languageDetection.undoing = true
        let token = run.token
        Task { [weak self] in
            do {
                try await recorder.switchLocale(to: Locale(identifier: change.from),
                                                replay: run.buffer) { [weak self] replayed, cut in
                    self?.switchedBack(change, replayed: replayed, run: run, cut: run.offset + cut)
                }
                guard let self else { return }
                self.languageDetection.undoing = false
                self.pin(change)
                self.languageDetection.undone(to: change.from, token: token)
            } catch {
                guard let self else { return }
                self.languageDetection.undoing = false
                switch self.state {
                case .recording:
                    self.message = "Could not switch transcription back to " +
                        "\(MobileLanguageDetection.displayName(change.from)): \(error.localizedDescription). " +
                        "Tap Undo to try again."
                case .stopping, .preparing: self.languageDetection.pendingUndo = true
                case .idle: self.finishUndo(change)
                }
            }
        }
    }

    /// The live transcriber is back in the original language. The switched recording's lines come back
    /// if it has already ended; this recording's lines are transcribed again when its audio is held.
    private func switchedBack(_ change: MobileLanguageDetection.Switch, replayed: Bool,
                              run: MobileLanguageDetection.Run, cut: TimeInterval) {
        if change.runToken != run.token { restoreLines(change) }
        if replayed {
            beginReplay(token: run.token, firstLine: run.firstLine, cut: cut)
        } else {
            languageDetection.replay?.discarded = true
            if change.runToken == run.token { restoreLines(change) }
        }
    }

    /// Undo once the recording has ended: the replaced lines come back and the language is pinned.
    func finishUndo(_ change: MobileLanguageDetection.Switch) {
        languageDetection.pendingUndo = false
        if change.conversation == id { restoreLines(change) }
        pin(change)
    }

    private func pin(_ change: MobileLanguageDetection.Switch) {
        languageDetection.clearNotice()
        language = change.from
        languageDetection.automatic = false
    }

    /// Lines a switch replaced come back in place of the switched recording's own lines before the
    /// switch. A switch that replaced nothing restores nothing.
    private func restoreLines(_ change: MobileLanguageDetection.Switch) {
        guard change.replayed else { return }
        let recording = change.recordingLines
            ?? Set(segments.dropFirst(change.firstLine).filter { !Self.isWatchLine($0) }.map(\.id))
        let restored = LanguageDetectionPolicy.restoring(change.originals, into: segments, recording: recording,
                                                         before: change.cut)
        guard restored != segments else { return }
        speechCorrection.cancel()
        segments = restored
        save(announce: false)
    }
}
