import Foundation
import ListenToMeCore

extension MeetingView {
    func identifySpeakers(showSheet: Bool = true) {
        if showSheet { showSpeakerBreakdown = true }
        guard diarizationSinkAttached, !speakerLoading else { return }
        speakerLoading = true
        // An explicit press is the retry gesture for a latched model-load failure (issue #109).
        let retryModels = showSheet
        let token = diarizationRunToken
        speakerWork.start(prepare: {
            if retryModels { await diarizer.retryModelLoad() }
        }, operation: {
            guard token == diarizationRunToken else { return }
            if retryModels { speakerStatus = nil }
            await analyzeSpeakers(token: token)
        })
    }

    /// Drain a periodic pass before a final pass, so Stop includes the transcriber's last utterance.
    func finishSpeakerAnalysis(expectedRun: Int? = nil) async {
        let token = expectedRun ?? diarizationRunToken
        guard token == diarizationRunToken else { return }
        await speakerWork.wait()
        guard token == diarizationRunToken, diarizationSinkAttached else { return }
        identifySpeakers(showSheet: false)
        await speakerWork.wait()
    }

    /// One pass over every attached channel. Returns nothing; all results land in `MeetingView`
    /// state. Cancelled/superseded runs bail through the run-token guards.
    private func analyzeSpeakers(token: Int) async {
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
        // growing session; voices and the overlap let SpeakerIdentityTracker carry identities over.
        let from = SpeakerAnalysisPolicy.windowStartSample(totalSamples: captured, analyzedSamples: analyzed)
        let snapshot = await sink.snapshotOffMain(fromSample: from)
        guard token == diarizationRunToken, !Task.isCancelled else { return .cancelled }
        guard snapshot.samples.count >= SpeakerAnalysisPolicy.minimumSamples else { return nil }
        do {
            let result = try await diarizer.analyze(samples: snapshot.samples)
            guard token == diarizationRunToken, !Task.isCancelled else { return .cancelled }
            speakerAnalyzedSamples[source] = snapshot.startSample + snapshot.samples.count
            // Transcript lines sit on the conversation's timeline, this run's audio from its own zero.
            applySpeakerResult(result, source: source, offset: snapshot.startOffset + session.recordingOffset,
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
        // Voices first (issue #171), so someone silent through the window's overlap keeps their name.
        let identities = tracker.reconcile(windowSegments, since: windowStart, embeddings: result.embeddings)
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
        guard !cleaned.isEmpty else { return }
        let normalized = String(cleaned.prefix(80))
        guard let source = SpeakerParticipant.rename(id: id, to: normalized,
            participants: &speakerParticipants, store: store) else { return }
        speakerTrackers[source]?.rename(id: id, name: normalized)
        speakerIdentities[source]?[id]?.name = normalized
        session.speakerNamesChanged()
        speakerCheckpoint.start(load: { await session.waitForResponse(.listener) }, apply: { _ in
            saveSessionIfEnabled(session: session, force: true)
        })
    }
    /// Pre-start half of a diarization-run reset: clear stale inline labels and bump the run token so
    /// any in-flight `identifySpeakers` drops its (now stale) results. Call this BEFORE `session.start()`
    /// — the run anchor is set only AFTER start returns (see `anchorDiarizationRun`), because
    /// `start()` awaits the prior Stop's drain, which can still append old final utterances first.
    ///
    /// Also release the breakdown UI: bumping the token makes a superseded `identifySpeakers` task
    /// bail via its token guard WITHOUT clearing `speakerLoading`, so we clear the spinner/error state
    /// here. This guarantees that starting/restarting always frees the "Identify speakers" button.
    func beginDiarizationRunReset() {
        speakerWork.cancel()
        speakerCheckpoint.cancel()
        let run = diarizationRunToken + 1
        let remotePrefix = run == 1 ? "Speaker" : "Run \(run) speaker"
        let micPrefix = run == 1 ? "Mic speaker" : "Run \(run) mic speaker"
        speakerTrackers = [.others: SpeakerIdentityTracker(prefix: remotePrefix),
                           .you: SpeakerIdentityTracker(prefix: micPrefix)]
        speakerParticipants = []
        speakerSegments = [:]
        speakerIdentities = [:]
        speakerAnalyzedSamples = [:]
        speakerStatus = nil
        // A new recording is also a retry: the model download may well succeed now (#109).
        speakerModelReset.start(load: { await diarizer.retryModelLoad() }, apply: { _ in })
        nextSpeakerAnalysis = .distantFuture
        speakerLoading = false
        speakerError = nil
        diarizationRunToken &+= 1
        // Every capture start passes here first: the next capture saves its audio into this conversation.
        // Audio only for a conversation History will keep (#55 review): none while autosaving is off.
        MacSavedAudio.shared.prepareRun(conversationID: ProviderSettings.saveSessionsForSearch && sessionSaveable
                                        ? currentSessionID : nil)
        // Disable Identify for the whole transition window: `session.start()` first awaits the prior
        // Stop's drain, then `makeCapture` calls `othersSink.reset()`. Until that reset+attach happens
        // the buffer still holds the PREVIOUS run's audio under the new token, so an Identify here
        // would slip a stale result past the token guard. We re-enable in `anchorDiarizationRun()`,
        // once start() has returned and the new run is fully live. The run snapshots are also taken
        // there (not here), so they reflect what the new capture/transcriber actually used.
        diarizationSinkAttached = false
        microphoneSinkAttached = false
    }

    /// Post-start half: anchor diarization to the current run and snapshot what it actually used. By
    /// the time `session.start()` returns, the previous run's drain is complete (its finals are in the
    /// store) and the new capture has reset+attached the sink, so `store.utterances.count` marks where
    /// this run's lines begin and the live settings match the capture/transcriber just built.
    func anchorDiarizationRun() {
        diarizationRunStartIndex = store.utterances.count
        MacSavedAudio.shared.anchorRun(firstSegment: store.utterances.count)
        // Snapshot the settings the new run's capture/transcriber were built from. `makeCapture` read
        // `speakerDiarizationEnabled` to decide sink attachment and `makeTranscriber` read the engine,
        // both during the `start()` that just returned — so reading them now matches this run, and
        // re-enables Identify only when the sink is actually attached and live.
        diarizationSinkAttached = ProviderSettings.speakerDiarizationEnabled
        diarizationRunUsesTimestamps = ProviderSettings.transcriptionEngine != "speechRecognizer"
        microphoneSinkAttached = diarizationSinkAttached && ProviderSettings.microphoneDiarizationEnabled
        nextSpeakerAnalysis = Date().addingTimeInterval(SpeakerAnalysisPolicy.minimumRest)
    }


}
