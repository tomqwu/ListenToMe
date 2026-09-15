import Foundation
import ListenToMeCore

extension MeetingView {
    func identifySpeakers(showSheet: Bool = true) {
        if showSheet { showSpeakerBreakdown = true }
        guard diarizationSinkAttached, !speakerLoading else { return }
        speakerLoading = true
        // An explicit press is the retry gesture for a latched model-load failure (issue #109).
        let retryModels = showSheet
        speakerTask = Task {
            if retryModels {
                await diarizer.retryModelLoad()
                speakerStatus = nil
            }
            await analyzeSpeakers()
        }
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
        var outcome = SpeakerAnalysisOutcome.completed
        var failureReason: String?
        let sources: [SpeakerSource] = microphoneSinkAttached ? [.others, .you] : [.others]
        for source in sources {
            let sink = source == .others ? othersAudioSink : microphoneAudioSink
            // Re-analyze only a trailing window since the previous pass (issue #109) instead of the
            // whole growing session; the overlap lets SpeakerIdentityTracker carry identities over.
            let from = SpeakerAnalysisPolicy.windowStartSample(totalSamples: sink.sampleCount,
                                                               analyzedSamples: speakerAnalyzedSamples[source] ?? 0)
            let snapshot = await Task.detached { sink.snapshot(fromSample: from) }.value
            guard token == diarizationRunToken, !Task.isCancelled else { return }
            guard snapshot.samples.count >= SpeakerAnalysisPolicy.minimumSamples else { continue }
            do {
                let result = try await diarizer.analyze(samples: snapshot.samples)
                guard token == diarizationRunToken, !Task.isCancelled else { return }
                speakerAnalyzedSamples[source] = snapshot.startSample + snapshot.samples.count
                applySpeakerResult(result, source: source, offset: snapshot.startOffset,
                                   windowStart: snapshot.startTime)
            } catch {
                guard token == diarizationRunToken, !Task.isCancelled else { return }
                speakerError = "\(source == .you ? "Microphone" : "System audio"): \(error.localizedDescription)"
                if let reason = (error as? SpeakerDiarizer.DiarizationError)?.modelFailureReason {
                    outcome = .modelsUnavailable
                    failureReason = reason
                }
            }
        }
        guard token == diarizationRunToken, !Task.isCancelled else { return }
        speakerLoading = false
        speakerStatus = SpeakerAnalysisPolicy.statusLine(for: outcome, detail: failureReason)
        // Avoid an ever-growing work queue: one pass at a time, with a rest at least as long as the
        // pass — and no periodic pass at all once the models are known to be unavailable.
        nextSpeakerAnalysis = SpeakerAnalysisPolicy.nextAnalysis(passStarted: started, finished: Date(),
                                                                 outcome: outcome) ?? .distantFuture
        if !wantsCapture {
            await session.waitForResponse(.listener)
            guard token == diarizationRunToken, !Task.isCancelled else { return }
            saveSessionIfEnabled(session: session, force: true)
        }
    }

    /// Folds one (possibly incremental) diarization pass into the session-wide picture.
    /// `windowStart` is the buffer-relative time of the analyzed window's first sample; the pass's
    /// own times are relative to that window, so they are shifted before anything else uses them.
    private func applySpeakerResult(_ result: SpeakerDiarizer.DiarizationOutcome,
                                    source: SpeakerSource, offset: TimeInterval,
                                    windowStart: TimeInterval) {
        let windowSegments = result.segments.map {
            DiarizedSegment(speakerId: $0.speakerId, start: $0.start + windowStart, duration: $0.duration)
        }
        var tracker = speakerTrackers[source] ?? SpeakerIdentityTracker()
        let identities = tracker.reconcile(windowSegments, since: windowStart)
        speakerTrackers[source] = tracker
        // Remember every identity ever seen: older passes' speakers stay in the cumulative timeline
        // even when this window did not hear them.
        var known = speakerIdentities[source] ?? [:]
        for identity in identities.values { known[identity.id] = identity }
        speakerIdentities[source] = known
        // Stitch: history before the window (already in identity-id space) + this window's segments.
        let merged = SpeakerStats.clip(speakerSegments[source] ?? [], endingAt: windowStart)
            + windowSegments.compactMap { segment in
                identities[segment.speakerId].map {
                    DiarizedSegment(speakerId: $0.id, start: segment.start, duration: segment.duration)
                }
            }
        speakerSegments[source] = merged
        speakerParticipants.removeAll { $0.source == source }
        speakerParticipants += SpeakerStats.summarize(merged).speakers.compactMap { speaker in
            guard let identity = known[speaker.id] else { return nil }
            return SpeakerParticipant(id: identity.id, name: identity.name, source: source, seconds: speaker.total)
        }
        guard diarizationRunUsesTimestamps else { return }
        // Use the latest finalized lines: transcription can finish while the audio pass runs.
        let transcript = Array(store.utterances.dropFirst(diarizationRunStartIndex)).filter { $0.source == source }
        let labeling = SpeakerLabeling.label(transcript: transcript, diarized: merged,
                                             offset: offset, source: source)
        let byLabel = Dictionary(uniqueKeysWithValues: labeling.order.compactMap { raw, label in
            known[raw].map { (label, $0) }
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
        speakerIdentities[source]?[id]?.name = normalized
        store.renameSpeaker(id: id, name: normalized)
        session.speakerNamesChanged()
        Task {
            await session.waitForResponse(.listener)
            saveSessionIfEnabled(session: session, force: true)
        }
    }
}
