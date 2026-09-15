import Foundation

// The automatic-review and live-evaluation wiring of `MeetingSession`: the memoized labeled-piece
// snapshot, the Quick evaluator loop, and the coordinator that runs full Summary/Deep reviews. Split
// out of MeetingSession.swift purely to keep each file readable; the members it reaches are
// module-internal rather than file-private for that reason alone.

extension MeetingSession {
    /// What the labeled piece snapshot is a function of. `store.revision` covers every change to
    /// finalized speech (arrival, restore, attribution, renaming); partials bump no revision, so
    /// their text is compared directly — keyed on the channel, whose identity is stable, not on a
    /// speaker label that a rename could change — along with the notes that become the `Notes:` piece.
    struct LiveKey: Equatable {
        let revision: Int
        let partials: [String]
        let notes: String
    }

    /// The memoized snapshot: the labeled pieces plus the joined review source built from them.
    /// Rebuilt only when `LiveKey` changes, so one `handleLiveEvent` walks the transcript once
    /// instead of three times plus a join (issue #116).
    struct LiveSnapshot {
        let pieces: [QuickSummaryContext.Piece]
        let source: String
    }

    func liveSnapshot() -> LiveSnapshot {
        let live = [SpeakerSource.you, .others].compactMap { store.partials[$0] }
        let key = LiveKey(revision: store.revision,
                          partials: live.map { $0.source.rawValue + ":" + $0.text },
                          notes: notes)
        if let cached = liveCache, liveCacheKey == key { return cached }
        let pieces = QuickSummaryContext.pieces(notes: notes, segments: store.utterances,
                                                liveSegments: live)
        // The pieces already carry speaker labels and a Notes marker, so the automatic reviews read
        // the same attributed evidence every manual prompt does.
        let snapshot = LiveSnapshot(pieces: pieces, source: pieces.map(\.text).joined(separator: "\n"))
        liveCacheKey = key
        liveCache = snapshot
        #if DEBUG
        livePieceComputations += 1
        #endif
        return snapshot
    }

    var livePieces: [QuickSummaryContext.Piece] { liveSnapshot().pieces }

    #if DEBUG
    /// Test-only: the memoized pieces, without going through the private accessor.
    var livePiecesForTesting: [QuickSummaryContext.Piece] { livePieces }
    #endif

    public var autoQuickStatus: String {
        guard autoSummaryEnabled else { return "Auto off" }
        guard aiEnabled else { return "Auto paused · AI is off" }
        if let reason = providerAvailability(models[.quick] ?? "") { return "Auto paused · " + reason }
        if let error = quickReader.error { return error }
        if quickReader.isCatchingUp { return "Catching up · Recap covers speech processed so far." }
        if quickReader.isReading { return "Checking new speech…" }
        if quickAnswerOverridesRecap { return "Recap updated · Showing your generated answer" }
        if quickReader.completedReads > 0, quickRecap.isEmpty { return "Speech checked · No takeaway yet" }
        return isRunning ? "Listening for meaningful changes" : "Auto checks while listening"
    }


    /// The user's language, persona and reference settings, applied to automatic reviews exactly as
    /// they are applied to the manual panes.
    private var automaticReviewDirectives: AutomaticReviewDirectives {
        AutomaticReviewDirectives(responseLanguage: responseLanguage, personaGuidance: personaGuidance,
                                  references: referenceContext)
    }

    public func automaticReviewStatus(_ mode: AutomaticReviewMode) -> String {
        guard autoSummaryEnabled else { return "Auto off · Generate manually." }
        guard isRunning else { return "Auto reviews run while listening. Generate is also available." }
        guard aiEnabled else { return "Auto paused · AI is off." }
        if let reason = providerAvailability(models[.quick] ?? "") { return "Auto paused · " + reason }
        guard providers[.quick] != nil else { return "Auto paused · Choose a Quick model." }
        return automaticReviews.status(mode)
    }

    func synchronizeAutomaticReviews() { synchronizeAutomaticReviews(liveSnapshot()) }

    /// - Parameter live: the snapshot for this event, computed once by the caller so a single
    ///   ingested hypothesis never walks the transcript more than once (issue #116).
    private func synchronizeAutomaticReviews(_ live: LiveSnapshot) {
        automaticReviews.synchronize(enabled: autoSummaryEnabled && isRunning && aiEnabled
            && providers[.quick] != nil && providerAvailability(models[.quick] ?? "") == nil,
            manualBusy: !streamingRoles.isEmpty, pieces: live.pieces, source: live.source,
            directives: automaticReviewDirectives, provider: { [weak self] mode in
                guard let self else { throw CancellationError() }
                let role: CopilotRole = mode == .summary ? .listener : .deep
                if let reason = self.providerAvailability(self.models[role] ?? "") { throw QuickSummaryError.message(reason) }
                guard let provider = self.providers[role] else { throw QuickSummaryError.message("Choose a review model.") }
                return provider
            }, apply: { [weak self] mode, output, reviewed in
                guard let self else { return }
                self.setOutput(mode == .summary ? .listener : .deep, output)
                if mode == .summary { self.lastCompletedListenerSummary = output }
                // The review still answers the current input when that input merely continued the
                // snapshot it read; otherwise the recommendation stays outstanding. Comparing the
                // joined source instead would re-run the identical review after a notes keystroke.
                guard QuickSummaryContext.isContinuation(of: reviewed, in: self.livePieces) else { return }
                self.quickReader.markReviewed(mode.rawValue)
                // Only the segments this review actually read advance the listener ledger; speech
                // that arrived after the snapshot still needs summarizing.
                if mode == .summary {
                    self.summarizedSegmentIDs.formUnion(Self.segmentIDs(in: reviewed))
                }
            })
    }

    /// The transcript segments a piece snapshot covers. Piece IDs are "<segment UUID>:<chunk>";
    /// notes and provisional `live:` pieces have no segment and are skipped.
    static func segmentIDs(in pieces: [QuickSummaryContext.Piece]) -> Set<UUID> {
        Set(pieces.compactMap { UUID(uuidString: $0.id.components(separatedBy: ":").first ?? "") })
    }

    func handleLiveEvent(_ event: LiveSummaryScheduler.Event) {
        if event == .conversationChanged || event == .providerChanged { automaticReviews.reset() }
        // One snapshot per event: the pieces, the joined review source and the pending check all
        // read the same memoized value instead of rebuilding the transcript three times (issue #116).
        let live = liveSnapshot()
        synchronizeAutomaticReviews(live)
        let pending = quickReader.context.hasChanges(live.pieces)
        if event == .automationChanged || event == .providerChanged, !pending, !quickReader.isCatchingUp {
            automaticReviews.offer(quickReader.recommendations, source: live.source)
        }
        let state = LiveSummaryScheduler.Snapshot(recording: isRunning, automatic: autoSummaryEnabled,
            pending: pending, reading: quickReader.isReading,
            manualQuick: streamingRoles.contains(.quick), available: aiEnabled && providers[.quick] != nil && providerAvailability(models[.quick] ?? "") == nil,
            failures: quickReader.failures)
        for action in liveScheduler.plan(event, state: state) {
            switch action {
            case .cancelWake: liveWake?.cancel(); liveWake = nil
            case .cancelEvaluation: quickReader.cancel()
            case .schedule(let delay):
                liveWake = Task { [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    self?.handleLiveEvent(.timerFired)
                }
            case .evaluate: Task { [weak self] in await self?.evaluateLiveQuick() }
            }
        }
    }

    private func evaluateLiveQuick() async {
        guard isRunning, aiEnabled, autoSummaryEnabled, !quickReader.isReading,
              !streamingRoles.contains(.quick), providerAvailability(models[.quick] ?? "") == nil, let provider = providers[.quick] else { return }
        defer { handleLiveEvent(.evaluationFinished) }
        let live = liveSnapshot()
        if live.pieces.isEmpty {
            quickReader.reset(); quickSuggestion = ""; quickRecap = ""; manualQuickAnswer.dismiss(); return
        }
        do {
            guard let batch = try quickReader.context.batch(live.pieces, summary: quickRecap,
                reviewsCompleted: quickReader.reviewsCompleted, pendingReviews: quickReader.recommendations,
                responseLanguage: responseLanguage) else { return }
            let run = runID
            let previousReads = quickReader.completedReads
            await quickReader.read(batch, provider: provider, isCurrent: { [weak self] in
                guard let self, self.runID == run, self.isRunning, self.autoSummaryEnabled, self.aiEnabled else { return false }
                return self.quickReader.context.isCurrent(batch, pieces: self.livePieces)
            }, apply: { [weak self] in self?.applyQuickRecap($0) })
            if quickReader.completedReads > previousReads, !quickReader.isCatchingUp {
                let current = liveSnapshot()
                synchronizeAutomaticReviews(current)
                automaticReviews.offer(quickReader.recommendations, source: current.source)
            }
        } catch { /* Encoding consists only of validated string data. A later event retries. */ }
    }
}
