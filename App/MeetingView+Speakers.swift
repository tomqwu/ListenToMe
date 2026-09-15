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

    /// One pass over every attached channel. Returns nothing; all results land in `MeetingView`
    /// state. Cancelled/superseded runs bail through the run-token guards.
    private func analyzeSpeakers() async {
        let token = diarizationRunToken
        let started = Date()
        speakerError = nil
        var outcome = SpeakerAnalysisOutcome.completed
        var failureReason: String?
        // Every channel's failure is reported: the microphone pass must not overwrite what the
        // system-audio pass had to say (and vice versa).
        var failures: [String] = []
        let sources: [SpeakerSource] = microphoneSinkAttached ? [.others, .you] : [.others]
        for source in sources {
            guard let failure = await analyzeSource(source, token: token) else { continue }
            guard token == diarizationRunToken, !Task.isCancelled else { return }
            if case .cancelled = failure { return }
            if case .failed(let message, let modelReason) = failure {
                failures.append(message)
                if let modelReason {
                    outcome = .modelsUnavailable
                    failureReason = modelReason
                }
            }
        }
        guard token == diarizationRunToken, !Task.isCancelled else { return }
        speakerError = failures.isEmpty ? nil : failures.joined(separator: "\n")
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

    /// Outcome of one channel's pass: nil = nothing to do / applied successfully.
    private enum SourcePassFailure {
        /// The run was superseded or cancelled while this channel was being analyzed.
        case cancelled
        /// `message` is for the sheet; `modelReason` is set only for a latched model-load failure.
        case failed(message: String, modelReason: String?)
    }

    /// Analyzes the trailing window of one channel and folds the result in.
    private func analyzeSource(_ source: SpeakerSource, token: Int) async -> SourcePassFailure? {
        let sink = source == .others ? othersAudioSink : microphoneAudioSink
        let analyzed = speakerAnalyzedSamples[source] ?? 0
        let captured = sink.sampleCount
        // Nothing new on this channel since the last pass — re-diarizing the same window would burn
        // CPU for an identical answer.
        guard SpeakerAnalysisPolicy.hasNewAudio(totalSamples: captured, analyzedSamples: analyzed) else { return nil }
        // Re-analyze only a trailing window since the previous pass (issue #109) instead of the whole
        // growing session; the overlap lets SpeakerIdentityTracker carry identities over.
        let from = SpeakerAnalysisPolicy.windowStartSample(totalSamples: captured, analyzedSamples: analyzed)
        let snapshot = await Task.detached { sink.snapshot(fromSample: from) }.value
        guard token == diarizationRunToken, !Task.isCancelled else { return .cancelled }
        guard snapshot.samples.count >= SpeakerAnalysisPolicy.minimumSamples else { return nil }
        do {
            let result = try await diarizer.analyze(samples: snapshot.samples)
            guard token == diarizationRunToken, !Task.isCancelled else { return .cancelled }
            speakerAnalyzedSamples[source] = snapshot.startSample + snapshot.samples.count
            applySpeakerResult(result, source: source, offset: snapshot.startOffset,
                               windowStart: snapshot.startTime)
            return nil
        } catch {
            guard token == diarizationRunToken, !Task.isCancelled else { return .cancelled }
            let label = source == .you ? "Microphone" : "System audio"
            return .failed(message: "\(label): \(error.localizedDescription)",
                           modelReason: (error as? SpeakerDiarizer.DiarizationError)?.modelFailureReason)
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
        // Stitch this window onto the cumulative timeline (already in identity-id space). `splice`
        // keeps the history whole when the window heard nothing in the stretch it overlaps.
        let identified: [DiarizedSegment] = windowSegments.compactMap { segment -> DiarizedSegment? in
            guard let identity = identities[segment.speakerId] else { return nil }
            return DiarizedSegment(speakerId: identity.id, start: segment.start,
                                   duration: segment.duration)
        }
        let merged = SpeakerStats.splice(history: speakerSegments[source] ?? [],
                                         window: identified, windowStart: windowStart)
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
