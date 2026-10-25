import Foundation

extension MeetingSession {
    // MARK: - Audio file transcription

    /// Transcribes audio pulled from `nextChunk` (e.g. an imported file) into the store, independent
    /// of live capture. `nextChunk` is called one chunk at a time and returns nil at end of input,
    /// so the transcriber's feed rate paces reading (no unbounded buffering). Creates its own
    /// transcriber, drains its segments into the store live, and finishes when input ends. Re-entry
    /// is ignored, and it waits for any prior transcriber to finish draining so two transcribers
    /// never run at once (avoids SFSpeechRecognizer's 1100 overlap error).
    ///
    /// `transcriber` lets the caller force a batch-friendly engine for imports (SpeechAnalyzer
    /// finalizes all fed audio, so fast-feeding is lossless); when nil the session's live factory
    /// is used.
    public func transcribeAudio(
        nextChunk: @escaping @Sendable () async throws -> AudioChunk?,
        transcriber makeTranscriber: (@Sendable () -> any Transcribing)? = nil
    ) async {
        guard !isTranscribingFile, !isRunning else { return }
        isTranscribingFile = true
        defer { isTranscribingFile = false }
        await stopDrain?.value
        stopDrain = nil
        startRecordingTimeline()
        let transcriber = (makeTranscriber ?? self.makeTranscriber)()
        await transcriber.setContextualStrings(contextualStrings)
        transcriptionStatusTask?.cancel()
        transcriptionStatusTask = Task {
            for await status in transcriber.statusUpdates { self.transcriptionStatus = status }
        }
        defer { transcriptionStatusTask?.cancel() }
        let segmentStream = transcriber.segments
        let drain = Task { [weak self] in
            for await segment in segmentStream {
                self?.applyTranscribedSegment(segment)
            }
        }
        // Warm the pipeline before reading the file so the first chunks don't sit behind one-time
        // model setup, and so a cancelled import isn't stuck inside `feed`. Waited for through
        // `prepareRacingCancellation` because the caller (window close) cancels the import task and
        // then awaits it: we must return as soon as we're cancelled even if the platform's download
        // call ignores cancellation.
        await Self.prepareRacingCancellation(transcriber)
        // Pace by audio duration so a long file can't be read into the transcriber's queue far
        // faster than it's processed: cap how far (in audio seconds) reading runs ahead of an
        // 8x-realtime budget. The clock starts AFTER the first feed so one-time SpeechAnalyzer
        // model setup/download isn't credited as throughput. Stops promptly on cancellation.
        var startWall = clock()
        var audioSecondsFed = 0.0
        var pacing = false
        var readFailure: String?
        do {
            while !Task.isCancelled, let chunk = try await nextChunk() {
                await transcriber.feed(chunk)
                if !pacing { startWall = clock(); pacing = true; continue }   // exclude setup time
                audioSecondsFed += Double(chunk.samples.count) / max(chunk.sampleRate, 1)
                let lead = audioSecondsFed - (clock() - startWall) * 8.0
                if lead > 8.0 {
                    try? await Task.sleep(nanoseconds: UInt64(min(lead, 5.0) * 1_000_000_000))
                }
            }
        } catch { readFailure = error.localizedDescription }
        await transcriber.finish()
        await drain.value
        if let failure = readFailure ?? (Task.isCancelled ? "The import was cancelled." : nil) {
            hasIncompleteImport = true
            transcriptionStatusTask?.cancel()
            await transcriptionStatusTask?.value
            transcriptionStatus = "Import stopped early: \(failure) The transcript is incomplete."
        }
    }

}
