import Foundation
import ListenToMeCore

extension MeetingView {
    func identifySpeakers(showSheet: Bool = true) {
        if showSheet { showSpeakerBreakdown = true }
        guard diarizationSinkAttached, !speakerLoading else { return }
        speakerLoading = true
        speakerTask = Task { await analyzeSpeakers() }
    }

    /// Drain a periodic pass before a final pass, so Stop includes the transcriber's last utterance.
    func finishSpeakerAnalysis() async {
        let token = diarizationRunToken
        await speakerTask?.value
        guard token == diarizationRunToken, diarizationSinkAttached else { return }
        identifySpeakers(showSheet: false)
        await speakerTask?.value
    }

    private func analyzeSpeakers() async {
        let token = diarizationRunToken
        let started = Date()
        speakerError = nil
        let sources: [SpeakerSource] = microphoneSinkAttached ? [.others, .you] : [.others]
        for source in sources {
            let sink = source == .others ? othersAudioSink : microphoneAudioSink
            let snapshot = await Task.detached { (samples: sink.snapshot(), offset: sink.startOffset) }.value
            guard token == diarizationRunToken, !Task.isCancelled else { return }
            guard snapshot.samples.count >= 48_000 else { continue }
            do {
                let result = try await diarizer.analyze(samples: snapshot.samples)
                guard token == diarizationRunToken, !Task.isCancelled else { return }
                applySpeakerResult(result, source: source, offset: snapshot.offset)
            } catch {
                guard token == diarizationRunToken, !Task.isCancelled else { return }
                speakerError = "\(source == .you ? "Microphone" : "System audio"): \(error.localizedDescription)"
            }
        }
        guard token == diarizationRunToken, !Task.isCancelled else { return }
        speakerLoading = false
        // Avoid an ever-growing work queue: one pass at a time, with a rest at least as long as the pass.
        nextSpeakerAnalysis = Date().addingTimeInterval(max(20, Date().timeIntervalSince(started)))
        if !wantsCapture {
            await session.waitForResponse(.listener)
            guard token == diarizationRunToken, !Task.isCancelled else { return }
            saveSessionIfEnabled(session: session, force: true)
        }
    }

    private func applySpeakerResult(_ result: SpeakerDiarizer.DiarizationOutcome,
                                    source: SpeakerSource, offset: TimeInterval) {
        var tracker = speakerTrackers[source] ?? SpeakerIdentityTracker()
        let identities = tracker.reconcile(result.segments)
        speakerTrackers[source] = tracker
        speakerParticipants.removeAll { $0.source == source }
        speakerParticipants += result.summary.speakers.compactMap { speaker in
            guard let identity = identities[speaker.id] else { return nil }
            return SpeakerParticipant(id: identity.id, name: identity.name, source: source, seconds: speaker.total)
        }
        guard diarizationRunUsesTimestamps else { return }
        // Use the latest finalized lines: transcription can finish while the audio pass runs.
        let transcript = Array(store.utterances.dropFirst(diarizationRunStartIndex)).filter { $0.source == source }
        let labeling = SpeakerLabeling.label(transcript: transcript, diarized: result.segments,
                                             offset: offset, source: source)
        let byLabel = Dictionary(uniqueKeysWithValues: labeling.order.compactMap { raw, label in
            identities[raw].map { (label, $0) }
        })
        let assignments = labeling.lineLabels.compactMapValues { byLabel[$0] }
        let changed = transcript.contains {
            $0.speakerID != assignments[$0.id]?.id || $0.speakerName != assignments[$0.id]?.name
        }
        store.attributeSpeakers(assignments, replacing: Set(transcript.map(\.id)))
        if changed { session.speakerAttributionsChanged() }
    }

    func renameSpeaker(id: String, name: String) {
        // Keep names on one line in prompts/exports; blank edits leave the current label intact.
        let cleaned = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !cleaned.isEmpty, let index = speakerParticipants.firstIndex(where: { $0.id == id }) else { return }
        let normalized = String(cleaned.prefix(80))
        let source = speakerParticipants[index].source
        speakerParticipants[index].name = normalized
        speakerTrackers[source]?.rename(id: id, name: normalized)
        store.renameSpeaker(id: id, name: normalized)
        session.speakerNamesChanged()
        Task {
            await session.waitForResponse(.listener)
            saveSessionIfEnabled(session: session, force: true)
        }
    }
}
