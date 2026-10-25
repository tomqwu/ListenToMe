import Foundation
import ListenToMeCore

/// The transcription language, and Automatic mode (issues #197 and #199): detect the spoken language on
/// this device from the first stretch of speech, switch the live transcriber if it differs and transcribe
/// the recording so far again; then re-check a trailing window about once a minute, and when another
/// language is confirmed, switch again and transcribe only the part since it changed.
extension MobileSession {
    /// The picker tag for Automatic.
    static let automaticLanguageTag = "automatic"
    /// The starting locale for live recordings and fallback for Watch imports. Watch imports pin
    /// their own detected or fixed locale before transcription; live switches stay recording-local.
    var transcriptionLanguage: String { languageDetection.automatic ? Locale.current.identifier : language }

    /// The Settings picker's selection: Automatic, or a fixed language.
    var languageChoice: String {
        get { languageDetection.automatic ? Self.automaticLanguageTag : language }
        set {
            invalidateRecordingSupport()
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
        let rechecks: String
        if let run = detection.run {
            let switches = run.tracker.switches
            rechecks = "\(switches) switch\(switches == 1 ? "" : "es") · " + (detection.lastRecheck ?? "none yet")
        } else {
            rechecks = "none (not recording in Automatic)"
        }
        return ["Transcription language: \(mode)",
                "Recording language: \(detection.run?.locale ?? "none")",
                "Language check: \(detection.lastResult ?? "not run")",
                "Language re-check: \(rechecks)",
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
    /// transcript. Notes the speech for the language checks, and returns true when a replay holds the
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
                end: offset + segment.end, speakerName: Self.microphoneLabel, language: recordingLanguage))
        }
        return true
    }

    /// Ends the language side of a recording, after the recorder has delivered its last result: a replay
    /// still held is committed as far as it got, the recording's lines are noted for Undo, and an Undo
    /// tapped while stopping is applied.
    func endLanguageRun() {
        if languageDetection.replay?.discarded == false { commitReplay(complete: false) }
        let lines = languageDetection.run.map { Set(recordingLines(of: $0).map(\.id)) }
        languageDetection.endRun(recordingLines: lines)
        if languageDetection.pendingUndo, state == .idle, let change = languageDetection.notice {
            finishUndo(change)
        }
    }

    /// Called for every speech event of a recording, in the recorder's own time. Starts a check when one
    /// is due; it runs on its own task, so recording never waits for it.
    func noteLanguageSpeech(_ segment: TranscriptSegment) {
        guard let request = languageDetection.noteSpeech(start: segment.start, end: segment.end) else { return }
        languageDetection.check = Task { [weak self] in await self?.checkLanguage(request) }
    }

    /// Runs Whisper over the requested window and acts on what the run's tracker makes of it.
    func checkLanguage(_ request: MobileLanguageDetection.Request) async {
        let detection = languageDetection
        defer { detection.finishedCheck(request.token) }
        guard let model = detection.model, detection.isCurrent(request.token) else { return }
        guard let samples = await detection.audio([request.window], token: request.token).first ?? nil else {
            detection.missed("its audio is no longer held", request: request)
            return
        }
        let guess: LanguageGuess
        let supported: [String]
        do {
            try await model.prepare()   // joins the download or load the first speech started
            guard detection.isCurrent(request.token) else { return }
            detection.beginChecking(request)
            guess = try await model.detect(samples: samples)
            supported = await model.supportedLocales()
        } catch {
            detection.missed(error.localizedDescription, request: request)
            return
        }
        guard state == .recording, let outcome = detection.record(guess, for: request, supported: supported) else {
            return
        }
        switch outcome {
        case .keep(let reason):
            detection.kept(guess, reason: Self.describe(reason), request: request)
        case .confirming(let locale):
            detection.confirming(guess, locale: locale, request: request)
        case .switchTo(let target, let since):
            await switchLanguage(to: target, guess: guess, since: since, request: request)
        case .locate(let target, let span):
            let since = await locateChange(in: span, to: target, model: model, request: request)
            await switchLanguage(to: target, guess: guess, since: since, request: request)
        }
    }

    /// Checks ten-second chunks of `span` to find where the language changed (issue #199), so only the
    /// part since then is transcribed again. Chunks without enough speech are not checked.
    private func locateChange(in span: Range<TimeInterval>, to target: String, model: any MobileLanguageIdentifying,
                              request: MobileLanguageDetection.Request) async -> TimeInterval {
        let detection = languageDetection
        guard let run = detection.run, run.token == request.token else { return span.lowerBound }
        let chunks = LanguageRecheckPolicy.scanChunks(span) { run.tracker.speech(in: $0) }
        let audio = await detection.audio(chunks, token: request.token)
        var scanned: [(chunk: Range<TimeInterval>, verdict: LanguageRecheckPolicy.Verdict)] = []
        for (chunk, samples) in zip(chunks, audio) {
            guard !Task.isCancelled, detection.isCurrent(request.token) else { break }
            guard let samples, let guess = try? await model.detect(samples: samples) else { continue }
            let verdict = LanguageRecheckPolicy.verdict(detected: guess.language, probability: guess.probability,
                                                        current: run.locale, target: target)
            scanned.append((chunk, verdict))
        }
        return LanguageRecheckPolicy.changePoint(in: span, scanned: scanned)
    }

    /// Restarts the live transcriber in `target`; it first hears the recording again from `since`
    /// (recording time; moved to a line boundary within the audio still held), and those lines replace
    /// the recording's once it has caught up. On failure the recording keeps its language and a status
    /// line says why.
    private func switchLanguage(to target: String, guess: LanguageGuess, since: TimeInterval,
                                request: MobileLanguageDetection.Request) async {
        let detection = languageDetection
        // Finding the change took a moment: an Undo or Stop since then wins.
        guard let recorder, let run = detection.run, run.token == request.token, state == .recording,
              detection.automatic, !detection.undoing else { return }
        detection.beginSwitch(to: target)
        let conversation = id, previous = run.locale, offset = run.offset, token = request.token
        let rate = TimeInterval(LanguageDetectionPolicy.sampleRate)
        var start = since
        var change: MobileLanguageDetection.Switch?
        var switchedAt: TimeInterval = 0
        do {
            // The start is chosen at the switch, once the new locale's assets are ready (a download can
            // take a while): from the audio still held then, so the replay is never lost to audio released
            // meanwhile (review of #212, finding 2).
            await recorder.setContextualStrings(vocabulary.recognitionTerms(for: id, localeIdentifier: target))
            try await recorder.switchLocale(to: Locale(identifier: target), replay: run.buffer, replayFrom: {
                start = self.replayStart(since, run: run)
                return Int((start * rate).rounded(.down))
            }, willReplace: { [weak self] replayed, cut in
                guard let self else { return }
                switchedAt = cut
                let replacing = replayed ? self.beginReplay(token: token, since: offset + start, cut: offset + cut)
                    : (firstLine: run.firstLine, lines: Array(self.segments.dropFirst(run.firstLine)))
                change = MobileLanguageDetection.Switch(
                    detected: guess.language, from: previous, to: target, conversation: conversation, runToken: token,
                    firstLine: replacing.firstLine, since: offset + start, cut: offset + cut,
                    replayFrom: Int((start * rate).rounded(.down)), originals: replacing.lines, replayed: replayed,
                    midRecording: !request.first, fromRecordingStart: start <= 0.001)
            })
        } catch {
            await recorder.setContextualStrings(vocabulary.recognitionTerms(for: id, localeIdentifier: previous))
            detection.switchFailed(error.localizedDescription, guess: guess, to: target, request: request)
            return
        }
        if let change { detection.switched(change, guess: guess, token: token, cut: switchedAt) }
    }

    /// Where transcribing again starts, in recording time: `since`, within the audio still held and at
    /// the start of a line rather than inside one.
    private func replayStart(_ since: TimeInterval, run: MobileLanguageDetection.Run) -> TimeInterval {
        var lines = recordingLines(of: run)
        if let partial { lines.append(partial) }
        let ranges = lines.map { ($0.start - run.offset)..<(max($0.start, $0.end) - run.offset) }
        return LanguageRecheckPolicy.replayStart(desired: since, retainedFrom: run.buffer.replayFloor, lines: ranges)
    }

    /// The recording's own lines: from its start (`offset`, which no earlier recording's line reaches
    /// past), never Apple Watch lines. Found by time rather than by index, which a restore of an earlier
    /// recording's lines shifts (review of #212, finding 6).
    func recordingLines(of run: MobileLanguageDetection.Run) -> [TranscriptSegment] {
        segments.filter { !Self.isWatchLine($0) && $0.start >= run.offset - 0.001 }
    }

    /// The new transcriber hears the recording again from `since` (transcript time). Its lines are held
    /// until it catches up, while the current lines stay on screen and on disk. The unfinished line
    /// becomes a line of its own, so an Undo can bring it back. Returns the lines it will replace (the
    /// recording's own lines from `since`; no earlier recording's line starts that late) and where the
    /// first of them is.
    @discardableResult
    func beginReplay(token: Int, since: TimeInterval,
                     cut: TimeInterval) -> (firstLine: Int, lines: [TranscriptSegment]) {
        speechCorrection.cancel()
        if let partial { segments.append(partial); self.partial = nil }
        let lines = segments.filter { !Self.isWatchLine($0) && $0.start >= since - 0.001 }
        let ids = Set(lines.map(\.id))
        languageDetection.replay = .init(token: token, since: since, cut: cut, replaced: ids)
        return (segments.firstIndex { ids.contains($0.id) } ?? segments.count, lines)
    }

    /// Puts the held replay lines in place of the lines the replay replaces, in one step, where the
    /// first of them was. Every other line stays where it is.
    private func commitReplay(complete: Bool) {
        guard let replay = languageDetection.replay else { return }
        languageDetection.replay = nil
        let originals = segments.filter { replay.replaced.contains($0.id) }
        let merged = LanguageDetectionPolicy.mergingReplay(replay.lines, over: originals, complete: complete)
        let position = segments.firstIndex { replay.replaced.contains($0.id) }
            ?? segments.firstIndex { !Self.isWatchLine($0) && $0.start >= replay.since - 0.001 } ?? segments.count
        var updated = segments.filter { !replay.replaced.contains($0.id) }
        updated.insert(contentsOf: merged, at: min(position, updated.count))
        guard updated != segments else { return }
        speechCorrection.cancel()
        segments = updated
        save(announce: false)
    }

    private static func describe(_ reason: LanguageDetectionPolicy.Reason) -> String {
        switch reason {
        case .pinned: return "fixed language"
        case .switchLimit: return "switch limit for this recording"
        case .lowConfidence: return "not confident"
        case .sameLanguage: return "same language"
        case .unsupported: return "no on-device transcription for it"
        }
    }
}
