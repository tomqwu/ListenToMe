import Foundation
import ListenToMeCore

/// Undo of a language switch (issues #197 and #199). A recording can switch more than once; Undo is for
/// the latest switch, and earlier ones stay.
extension MobileSession {
    /// Undo is offered for the open conversation's switch, except while a recording is starting or an
    /// Undo is already switching back. While stopping, a tap is kept and applied once Stop finishes.
    var canUndoLanguageSwitch: Bool {
        languageDetection.notice?.conversation == id && !languageDetection.undoing && state != .preparing
    }

    /// Undo pins the language the recording was in before the switch, for this and later recordings.
    /// While recording, transcription switches back first, and the notice stays until that has worked;
    /// once stopped, the lines the switch replaced come back.
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
        // What the switch changed is heard again: its own span in this recording, or all of a recording
        // that resumed the switched conversation. Without that audio, the replaced lines come back instead.
        let sameRun = change.runToken == run.token
        let from = sameRun ? change.replayFrom : 0
        let held = Int(run.buffer.replayFloor * TimeInterval(LanguageDetectionPolicy.sampleRate))
        let replay = from >= held ? run.buffer : nil
        let since = sameRun ? change.since : run.offset
        Task { [weak self] in
            do {
                try await recorder.switchLocale(to: Locale(identifier: change.from), replay: replay,
                                                from: from) { [weak self] replayed, cut in
                    self?.switchedBack(change, replayed: replayed, run: run, since: since, cut: run.offset + cut)
                }
                guard let self else { return }
                self.languageDetection.undoing = false
                self.pin(change)
                self.languageDetection.undone(to: change.from, token: token, midRecording: change.midRecording)
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
    /// if it has already ended; this recording's lines from `since` are transcribed again when their
    /// audio is held.
    private func switchedBack(_ change: MobileLanguageDetection.Switch, replayed: Bool,
                              run: MobileLanguageDetection.Run, since: TimeInterval, cut: TimeInterval) {
        if change.runToken != run.token { restoreLines(change) }
        if replayed {
            beginReplay(token: run.token, run: run, since: since, cut: cut)
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

    /// Lines a switch replaced come back in place of the switched recording's own lines from where it
    /// transcribed again to the switch. A switch that replaced nothing restores nothing.
    private func restoreLines(_ change: MobileLanguageDetection.Switch) {
        guard change.replayed else { return }
        let recording = change.recordingLines
            ?? Set(segments.dropFirst(change.firstLine).filter { !Self.isWatchLine($0) }.map(\.id))
        let restored = LanguageDetectionPolicy.restoring(change.originals, into: segments, recording: recording,
                                                         since: change.since, before: change.cut)
        guard restored != segments else { return }
        speechCorrection.cancel()
        segments = restored
        save(announce: false)
    }
}
