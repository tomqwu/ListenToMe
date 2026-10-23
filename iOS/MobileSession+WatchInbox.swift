import Foundation
import ListenToMeCore

/// A watch recording still in the inbox: parts waiting to be transcribed, or a failure to retry.
struct WatchInboxRow: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let waitingParts: Int
    let failure: String?

    var title: String { "Apple Watch · " + startedAt.formatted(date: .abbreviated, time: .shortened) }
    var detail: String { failure ?? (waitingParts == 1 ? "1 part waiting" : "\(waitingParts) parts waiting") }
}

/// Apple Watch recordings become conversations (issue #181). The drain runs only in the foreground
/// while the phone is idle: it never starts audio, never switches the open conversation, and deletes
/// a chunk's audio only after the text it became is saved (decision 3).
extension MobileSession {
    static let watchAddedMessage = "Apple Watch recording added to History."
    static let watchUnexpectedEndNote =
        "This Apple Watch recording ended unexpectedly. The last few minutes may be missing."

    /// The share-import idempotency key, reused for watch recordings.
    static func watchSourceID(_ recordingID: UUID) -> String { "watch:" + recordingID.uuidString }

    static func watchGapNote(minutes: Int) -> String {
        "Part of this recording (about \(minutes) min) did not arrive from Apple Watch."
    }

    /// Starts transcribing waiting watch recordings when the app is active and idle. Triggered on
    /// `.active`, when the session stops being busy, and when a chunk arrives.
    func importWatchInbox(now: Date = Date()) {
        refreshWatchInboxRows()
        guard applicationIsActive(), state == .idle, !isSummarizing, watchDrainTask == nil else { return }
        guard watchInbox.ledgers().contains(where: { Self.hasWork($0.nextBatch(now: now)) }) else { return }
        watchDrainTask = Task { [weak self] in
            await self?.drainWatchInbox(now: now)
            self?.watchDrainTask = nil
            self?.refreshWatchInboxRows()
        }
    }

    // MARK: History

    static func isFromAppleWatch(_ record: SessionRecord) -> Bool {
        record.sourceImportID?.hasPrefix("watch:") == true
    }

    func refreshWatchInboxRows() {
        let rows = watchInbox.ledgers().compactMap { ledger -> WatchInboxRow? in
            let waiting = ledger.chunks.filter { $0.state == .received }.count
            guard waiting > 0 || ledger.failure != nil else { return nil }
            return WatchInboxRow(id: ledger.recordingID, startedAt: ledger.startedAt, waitingParts: waiting,
                                 failure: ledger.failure)
        }
        if rows != watchInboxRows { watchInboxRows = rows }
    }

    /// The user's Retry on a failed recording.
    func retryWatchRecording(_ recordingID: UUID) {
        _ = try? watchInbox.update(recordingID) { $0.clearFailure() }
        importWatchInbox()
    }

    /// Deletes the recording's audio. Text already transcribed stays in its conversation.
    func deleteWatchRecording(_ recordingID: UUID) {
        let drain = watchDrainTask
        drain?.cancel()
        do {
            try watchInbox.removeRecording(recordingID)
        } catch {
            message = "Could not delete the Apple Watch audio: \(error.localizedDescription)"
        }
        refreshWatchInboxRows()
        // Any other recording the cancelled drain was going to transcribe resumes.
        if drain != nil {
            Task { [weak self] in
                await drain?.value
                self?.importWatchInbox()
            }
        }
    }

    // MARK: Drain

    /// The open conversation could not be saved, or the watch conversation was deleted meanwhile.
    /// Nothing is marked done; the recording is tried again at the next foreground.
    private struct WatchConversationUnavailable: Error {}

    private static func hasWork(_ batch: WatchLedgerBatch) -> Bool {
        !batch.indices.isEmpty || !batch.newGaps.isEmpty || batch.finishes
    }

    /// Oldest recording first. A failure stops that recording only.
    private func drainWatchInbox(now: Date) async {
        for ledger in watchInbox.ledgers() where Self.hasWork(ledger.nextBatch(now: now)) {
            guard !Task.isCancelled else { return }
            do {
                try await drainWatchRecording(ledger.recordingID, now: now)
            } catch is CancellationError {
                return
            } catch let error where error is WatchConversationUnavailable || Self.isTransient(error) {
                continue
            } catch {
                if Task.isCancelled { return }
                let reason = error.localizedDescription
                _ = try? watchInbox.update(ledger.recordingID) { $0.markFailed(reason) }
                message = "Could not transcribe an Apple Watch recording: \(Self.sentence(reason)) "
                    + "It is kept in History, where you can retry or delete it."
            }
        }
    }

    private func drainWatchRecording(_ recordingID: UUID, now: Date) async throws {
        guard var ledger = watchInbox.ledger(recordingID) else { return }
        let recordID = try watchRecordID(for: ledger)
        // A recording reopened after it finished (Continue, or a chunk the watch sent again), or one
        // whose text was saved just before the app stopped: what the conversation already holds is
        // not transcribed again.
        if ledger.transcribedThrough == 0, !ledger.chunks.contains(where: { $0.state == .transcribed }),
           let saved = history.first(where: { $0.id == recordID })?.segments?.map(\.end).max(), saved > 0 {
            ledger = try markWatchTranscribed(recordingID, through: saved) ?? ledger
        }
        while true {
            try Task.checkCancellation()
            let batch = ledger.nextBatch(now: now)
            guard Self.hasWork(batch) else { return }
            if batch.indices.isEmpty, batch.newGaps.isEmpty {
                try finishWatchRecording(ledger, recordID: recordID, now: now)
                return
            }
            if !batch.newGaps.isEmpty {
                let note = batch.newGaps.map { Self.watchGapNote(minutes: ledger.gapMinutes($0)) }
                    .joined(separator: "\n")
                try updateWatchRecord(recordID, note: note)
                _ = try watchInbox.update(recordingID) { $0.noteGaps(batch.newGaps) }
            }
            try await transcribeWatchChunks(batch.indices, of: ledger, recordID: recordID)
            // Re-read: chunks may have arrived while this batch was transcribing.
            guard let fresh = watchInbox.ledger(recordingID) else { return }
            ledger = fresh
        }
    }

    private func transcribeWatchChunks(_ indices: [Int], of ledger: WatchCaptureLedger, recordID: String) async throws {
        let recordingID = ledger.recordingID
        let chunks = indices.compactMap { index in ledger.chunks.first { $0.index == index } }.map {
            WatchAudioChunk(index: $0.index, url: watchInbox.chunkURL(recordingID: recordingID, index: $0.index),
                            startOffset: $0.startOffset, duration: $0.duration)
        }
        guard let end = chunks.map({ $0.startOffset + $0.duration }).max() else { return }
        // Lines before this point were saved before an interruption; a resumed pass hears them again.
        let resumeAt = ledger.transcribedThrough - 0.05
        try await makeWatchTranscriber().transcribe(chunks, locale: Locale(identifier: language)) { [weak self] line in
            guard let self, line.start >= resumeAt else { return }
            try self.updateWatchRecord(recordID, segment: TranscriptSegment(
                source: .you, text: line.text, isFinal: true, start: line.start, end: line.end,
                speakerName: MobileFileTranscriber.speakerName))
            try self.markWatchTranscribed(recordingID, through: line.end)
        }
        try markWatchTranscribed(recordingID, through: end)
    }

    private func finishWatchRecording(_ ledger: WatchCaptureLedger, recordID: String, now: Date) throws {
        let notes = history.first { $0.id == recordID }?.notes ?? ""
        let unexpected = ledger.endedUnexpectedly && !notes.contains(Self.watchUnexpectedEndNote)
        try updateWatchRecord(recordID, note: unexpected ? Self.watchUnexpectedEndNote : nil, complete: true)
        // Not removed if a chunk arrived since: the next drain picks it up.
        guard try watchInbox.removeFinishedRecording(ledger.recordingID, now: now) else { return }
        message = Self.watchAddedMessage
    }

    /// Marks text saved through `time` and only then deletes the audio it wholly covers.
    @discardableResult
    private func markWatchTranscribed(_ recordingID: UUID, through time: TimeInterval) throws -> WatchCaptureLedger? {
        let result = try watchInbox.update(recordingID) { ledger -> ([Int], WatchCaptureLedger) in
            (ledger.markTranscribed(through: time), ledger)
        }
        guard let (covered, ledger) = result else { return nil }
        watchInbox.deleteChunks(covered, of: recordingID)
        return ledger
    }

    // MARK: The conversation

    /// The conversation for a watch recording, created in History the first time.
    private func watchRecordID(for ledger: WatchCaptureLedger) throws -> String {
        let source = Self.watchSourceID(ledger.recordingID)
        if let existing = history.first(where: { $0.sourceImportID == source }) { return existing.id }
        let title = "Apple Watch · " + ledger.startedAt.formatted(date: .abbreviated, time: .shortened)
        let record = SessionRecord(id: UUID().uuidString, title: title, date: ledger.startedAt,
                                   transcript: "", summary: "", segments: [], notes: "",
                                   isComplete: false, sourceImportID: source)
        try archive.save(record)
        remember(record)
        return record.id
    }

    /// Adds a line and/or a note to a watch conversation where it lives now: through the live
    /// session when it is the open conversation (so nothing typed there is lost), otherwise in the
    /// archive. Throws unless the change is saved.
    private func updateWatchRecord(_ recordID: String, segment: TranscriptSegment? = nil, note: String? = nil,
                                   complete: Bool = false) throws {
        if recordID == id {
            if let segment { segments.append(segment) }
            if let note { notes = Self.appendingLine(note, to: notes) }
            guard save(announce: false) else { throw WatchConversationUnavailable() }
            return
        }
        guard let record = history.first(where: { $0.id == recordID }) else { throw WatchConversationUnavailable() }
        let lines = (record.segments ?? []) + (segment.map { [$0] } ?? [])
        let updated = SessionRecord(id: record.id, title: record.title, date: record.date,
                                    transcript: Self.transcriptText(for: lines), summary: record.summary,
                                    segments: lines, notes: note.map { Self.appendingLine($0, to: record.notes ?? "") }
                                        ?? record.notes,
                                    quickSuggestion: record.quickSuggestion, deepAnswer: record.deepAnswer,
                                    isComplete: complete, attachments: record.attachments,
                                    sourceImportID: record.sourceImportID)
        try archive.save(updated)
        remember(updated)
    }

    private static func appendingLine(_ line: String, to text: String) -> String {
        text.isEmpty ? line : text + "\n" + line
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return "Unknown error." }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}
