import Foundation
import ListenToMeCore

/// Speaker labels on the transcript (issue #180). Identification itself lives in `MobileSpeakers`;
/// this maps its passes onto the conversation's lines, and keeps renames in the saved record.
extension MobileSession {
    /// The label every recorded line starts with, and keeps when no speaker covers it confidently.
    static let microphoneLabel = "Microphone"

    struct SpeakerEntry: Identifiable, Equatable {
        let id: String
        let name: String
        let lines: Int
    }

    /// Speakers named on this conversation's transcript, in order of first appearance. Read from the
    /// lines themselves, so the list survives save, reopen and export without extra state.
    var speakerList: [SpeakerEntry] {
        var order: [String] = []
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for segment in segments {
            guard let id = segment.speakerID else { continue }
            if names[id] == nil { order.append(id) }
            names[id] = segment.speakerName ?? id
            counts[id, default: 0] += 1
        }
        return order.map { SpeakerEntry(id: $0, name: names[$0] ?? $0, lines: counts[$0] ?? 0) }
    }

    var hasSpeakerLabels: Bool { segments.contains { $0.speakerID != nil } }

    /// Periodic passes while recording. The first waits `SpeakerAnalysisPolicy.minimumRest`, so a
    /// short recording costs one pass, at Stop.
    func startSpeakerLoop() {
        speakerLoop?.cancel()
        guard speakers.isRunning else { speakerLoop = nil; return }
        speakerLoop = Task { [weak self] in
            var delay = SpeakerAnalysisPolicy.minimumRest
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.state == .recording else { return }
                delay = await self.periodicSpeakerPass()
            }
        }
    }

    /// One tick of the periodic loop; returns the seconds until the next one. A latched model failure
    /// stops passes until the user retries; the tick then only keeps memory flat.
    func periodicSpeakerPass() async -> TimeInterval {
        speakers.releaseAnalyzedAudio()
        guard !speakers.isUnavailable else { return SpeakerAnalysisPolicy.minimumRest }
        let started = Date()
        let outcome = await runSpeakerPass()
        let next = SpeakerAnalysisPolicy.nextAnalysis(passStarted: started, finished: Date(), outcome: outcome)
            ?? Date().addingTimeInterval(SpeakerAnalysisPolicy.minimumRest)
        return max(1, next.timeIntervalSinceNow)
    }

    /// One pass over the audio not yet analyzed, applied to this conversation's lines. `token`
    /// restricts it to one recording's run; the result is dropped if the open conversation changed.
    @discardableResult
    func runSpeakerPass(token: Int? = nil) async -> SpeakerAnalysisOutcome {
        let conversation = id
        if let pass = await speakers.analyze(token: token), id == conversation { applySpeakerLabels(pass) }
        return speakers.isUnavailable ? .modelsUnavailable : .completed
    }

    /// Called by Stop once the session is already idle and saved, so nothing here can hold Stop,
    /// New, History or backgrounding. The periodic loop is cancelled without waiting for it; a pass
    /// still running finishes on its own and its result is dropped if the run or conversation moved
    /// on. In the foreground, one final pass labels the last words, queued behind any pass in flight
    /// and limited to this run. It is skipped in the background (iOS gives a backgrounded app no
    /// Neural Engine) and until the models have loaded once, so Stop never starts the first download;
    /// those lines keep "Microphone".
    func finishSpeakerIdentification() {
        speakerLoop?.cancel()
        speakerLoop = nil
        guard speakers.isRunning else { return }
        guard isForeground, speakers.modelsReady else { speakers.endRun(); return }
        let token = speakers.runToken
        speakerFinalPass = Task { [weak self] in
            guard let self else { return }
            await self.runSpeakerPass(token: token)
            if self.speakers.runToken == token { self.speakers.endRun() }
        }
    }

    /// The retry gesture after the speaker models could not be loaded.
    func retrySpeakerIdentification() {
        let token = speakers.runToken
        Task {
            await speakers.retry()
            guard state == .recording else { return }
            await runSpeakerPass(token: token)
        }
    }

    /// Labels this recording's lines with the speaker whose speech covers them; lines no speaker
    /// covers confidently keep (or return to) "Microphone".
    func applySpeakerLabels(_ pass: MobileSpeakers.Pass) {
        guard pass.firstLine <= segments.count else { return }
        let assigned = SpeakerLabeling.assign(transcript: Array(segments[pass.firstLine...]), diarized: pass.timeline,
                                              identities: pass.identities, offset: pass.offset, source: .you,
                                              minimumCoverage: MobileSpeakers.minimumCoverage)
        var updated = segments
        for index in pass.firstLine..<updated.count {
            let identity = assigned[updated[index].id]
            updated[index].speakerID = identity?.id
            updated[index].speakerName = identity?.name ?? Self.microphoneLabel
        }
        replaceSpeakerLabels(updated)
    }

    /// Renames one speaker everywhere on this conversation's transcript. Saved at once; no AI work
    /// starts, and lines already read by Auto summaries are not sent again for the new name.
    func renameSpeaker(id speakerID: String, to name: String) {
        let cleaned = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let normalized = String(cleaned.prefix(80))
        guard !normalized.isEmpty, normalized != Self.microphoneLabel else { return }
        speakers.rename(id: speakerID, name: normalized)
        var updated = segments
        for index in updated.indices where updated[index].speakerID == speakerID {
            updated[index].speakerName = normalized
        }
        replaceSpeakerLabels(updated)
    }

    /// A label change is not new speech: the Quick ledger is carried over before the transcript
    /// changes, so the next automatic check does not re-read every relabeled line.
    private func replaceSpeakerLabels(_ updated: [TranscriptSegment]) {
        guard updated != segments else { return }
        quickReader.relabel(from: segments.map(Self.promptSegment), to: updated.map(Self.promptSegment))
        segments = updated
        save(announce: false)
    }
}
