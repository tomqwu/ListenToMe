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

    /// Lines are saved in batches of at most this many, or this often, and whenever a chunk's end
    /// is reached; a chunk's audio is deleted only after the save that covers it.
    static let watchLinesPerSave = 25
    static let watchSaveInterval: TimeInterval = 10

    /// Starts transcribing waiting watch recordings when the app is active and idle. Triggered on
    /// `.active`, when the session stops being busy, and when a chunk arrives. A chunk that arrives
    /// while a drain runs is picked up as soon as that drain ends.
    func importWatchInbox(now: Date = Date()) {
        refreshWatchInboxRows()
        guard applicationIsActive(), state == .idle, !isSummarizing else { return }
        guard watchDrainTask == nil else { watchDrainRequested = true; return }
        watchInbox.tidy(now: now)
        refreshWatchInboxRows()
        let ledgers = watchInbox.ledgers()
        guard ledgers.contains(where: { hasWatchWork($0, now: now) }) else { return }
        watchDrainRequested = false
        watchDrainTask = Task { [weak self] in
            await self?.drainWatchInbox(now: now)
            let cancelled = Task.isCancelled
            guard let self else { return }
            self.watchDrainTask = nil
            self.refreshWatchInboxRows()
            if !cancelled, self.watchDrainRequested {
                self.watchDrainRequested = false
                self.importWatchInbox()
            }
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
        let problems = watchInbox.problems()
        if problems != watchInboxProblems { watchInboxProblems = problems }
    }

    /// The user has read why some watch audio could not be kept.
    func dismissWatchInboxProblems() {
        watchInbox.clearProblems()
        refreshWatchInboxRows()
    }

    /// Deleted watch conversations take their raw audio with them, so the drain cannot bring them back,
    /// and leave tombstones so a part the watch sends again is discarded (#191). Run by the
    /// conversation-deletion path (MobileSession+Deletion.swift); throws if any audio remains.
    func discardWatchAudio(sourceImportIDs: [String]) throws {
        let recordings = sourceImportIDs.compactMap { source -> UUID? in
            guard source.hasPrefix("watch:") else { return nil }
            return UUID(uuidString: String(source.dropFirst("watch:".count)))
        }
        guard !recordings.isEmpty else { return }
        try removeWatchRecordings(recordings, tombstoneAt: Date())
    }

    /// The user's Retry on a failed recording.
    func retryWatchRecording(_ recordingID: UUID) {
        _ = try? watchInbox.update(recordingID) { $0.clearFailure() }
        importWatchInbox()
    }

    /// Deletes the recording's audio. Text already transcribed stays in its conversation.
    func deleteWatchRecording(_ recordingID: UUID) {
        do { try removeWatchRecordings([recordingID], tombstoneAt: nil) } catch {
            message = "Could not delete the Apple Watch audio: \(error.localizedDescription)"
        }
    }

    /// Stops a drain that may be transcribing them, removes the recordings, and lets the drain resume
    /// for every other recording. A `deletedAt` leaves a tombstone; see
    /// `WatchInbox.removeRecording(_:tombstoneAt:)`. Every recording is tried; the first error is thrown.
    private func removeWatchRecordings(_ recordingIDs: [UUID], tombstoneAt deletedAt: Date?) throws {
        let drain = watchDrainTask
        drain?.cancel()
        defer {
            refreshWatchInboxRows()
            // Any other recording the cancelled drain was going to transcribe resumes.
            if drain != nil {
                Task { [weak self] in
                    await drain?.value
                    self?.importWatchInbox()
                }
            }
        }
        var failure: Error?
        for recordingID in recordingIDs {
            watchSpeakerContexts[recordingID] = nil
            do { try watchInbox.removeRecording(recordingID, tombstoneAt: deletedAt) } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }

    // MARK: Drain

    /// The open conversation could not be saved, or the watch conversation was deleted meanwhile.
    /// Nothing is marked done; the recording is tried again at the next foreground.
    private struct WatchConversationUnavailable: Error {}

    private static func hasWork(_ batch: WatchLedgerBatch) -> Bool {
        !batch.indices.isEmpty || !batch.newGaps.isEmpty || batch.finishes
    }

    /// Saved text can settle missing earlier parts after the user deletes the inbox. Let that
    /// reconciliation run before deciding a later Continue part must wait for the gap timeout.
    private func hasWatchWork(_ ledger: WatchCaptureLedger, now: Date) -> Bool {
        if Self.hasWork(ledger.nextBatch(now: now)) { return true }
        guard ledger.failure == nil, !ledger.completed,
              let record = history.first(where: { $0.sourceImportID == Self.watchSourceID(ledger.recordingID) })
        else { return false }
        return savedWatchLinesEnd(record.id) != nil
    }

    /// Oldest recording first. A failure stops that recording only.
    private func drainWatchInbox(now: Date) async {
        for ledger in watchInbox.ledgers() where hasWatchWork(ledger, now: now) {
            guard !Task.isCancelled else { return }
            do {
                try await drainWatchRecording(ledger.recordingID, now: now)
            } catch is CancellationError {
                watchSpeakerContexts[ledger.recordingID] = nil
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
        guard let stored = watchInbox.ledger(recordingID) else { return }
        var ledger = try reconcileWithSavedLines(stored)
        guard Self.hasWork(ledger.nextBatch(now: now)) else { return }
        let recordID = try watchRecordID(for: ledger)
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
        var chunks = indices.compactMap { index in ledger.chunks.first { $0.index == index } }.map {
            WatchAudioChunk(index: $0.index, url: watchInbox.chunkURL(recordingID: recordingID, index: $0.index),
                            startOffset: $0.effectiveOffset, duration: $0.effectiveDuration)
        }
        chunks = try retainWatchAudio(chunks, ledger: ledger, recordID: recordID)
        guard let end = chunks.map({ $0.startOffset + $0.duration }).max() else { return }
        // Lines before this point were saved before an interruption; a resumed pass hears them again.
        let resumeAt = ledger.transcribedThrough - 0.05
        let pending = WatchLineBuffer(coveredThrough: ledger.transcribedThrough,
                                      chunkEnds: chunks.map { $0.startOffset + $0.duration })
        do {
            let language = try await watchTranscriptionLocale(ledger, chunks: chunks, recordID: recordID)
            let labels = try await watchSpeakerLabels(chunks, recordID: recordID, recordingID: recordingID)
            let transcriber = makeWatchTranscriber()
            transcriber.setContextualStrings(vocabulary.recognitionTerms(for: recordID, localeIdentifier: language))
            try await transcriber.transcribe(chunks, locale: Locale(identifier: language)) { [weak self] line in
                guard let self, line.start >= resumeAt else { return }
                var segment = TranscriptSegment(source: .you, text: line.text, isFinal: true, start: line.start,
                                                end: line.end, speakerName: MobileFileTranscriber.speakerName,
                                                language: language)
                if self.speakers.enabled { segment = labels.label(segment) }
                pending.lines.append(segment)
                if pending.shouldSave(after: line) {
                    try self.saveWatchLines(pending, recordID: recordID, of: recordingID)
                }
            }
        } catch {
            // Text heard before the stop is kept; its audio goes only where the text covers it whole.
            try? saveWatchLines(pending, recordID: recordID, of: recordingID)
            throw error
        }
        try saveWatchLines(pending, recordID: recordID, of: recordingID)
        try markWatchTranscribed(recordingID, through: end)
    }

    /// Saves the lines heard so far, then marks them transcribed and deletes audio they cover.
    private func saveWatchLines(_ pending: WatchLineBuffer, recordID: String, of recordingID: UUID) throws {
        guard let through = pending.lines.map(\.end).max() else { return }
        let lines = pending.lines
        pending.lines = []
        pending.lastSave = Date()
        try updateWatchRecord(recordID, segments: lines)
        pending.coveredThrough = max(pending.coveredThrough, through)
        try markWatchTranscribed(recordingID, through: through)
    }

    private func finishWatchRecording(_ ledger: WatchCaptureLedger, recordID: String, now: Date) throws {
        let notes = history.first { $0.id == recordID }?.notes ?? ""
        let unexpected = ledger.endedUnexpectedly && !notes.contains(Self.watchUnexpectedEndNote)
        try updateWatchRecord(recordID, note: unexpected ? Self.watchUnexpectedEndNote : nil, complete: true)
        // Kept open if a chunk arrived since: the next drain picks it up.
        guard try watchInbox.completeRecording(ledger.recordingID, now: now) else { return }
        watchSpeakerContexts[ledger.recordingID] = nil
        message = Self.watchAddedMessage
        nameConversationIfNeeded(recordID, language: ledger.transcriptionLocale ?? transcriptionLanguage)   // #221
    }

    /// Marks text saved through `time` and only then deletes the audio it wholly covers.
    @discardableResult
    private func markWatchTranscribed(_ recordingID: UUID, through time: TimeInterval,
                                      settleBelow: Int? = nil) throws -> WatchCaptureLedger? {
        let result = try watchInbox.update(recordingID) { ledger -> ([Int], WatchCaptureLedger) in
            if let settleBelow { ledger.settle(below: settleBelow) }
            return (ledger.markTranscribed(through: time), ledger)
        }
        guard let (covered, ledger) = result else { return nil }
        watchInbox.deleteChunks(covered, of: recordingID)
        return ledger
    }

    /// What the conversation already holds is not transcribed again. A crash between saving lines and
    /// marking them leaves the manifest behind the text, so it is moved up to the saved lines. A
    /// manifest that starts over for a conversation that already has watch lines (the audio was
    /// deleted from History, or the manifest was unreadable) settles every chunk before the first one
    /// it holds, instead of waiting a day for chunks that are already text.
    private func reconcileWithSavedLines(_ ledger: WatchCaptureLedger) throws -> WatchCaptureLedger {
        let source = Self.watchSourceID(ledger.recordingID)
        guard let record = history.first(where: { $0.sourceImportID == source }),
              let saved = savedWatchLinesEnd(record.id) else { return ledger }
        let startsOver = ledger.settledBelow == 0 && ledger.notedGaps.isEmpty && ledger.transcribedThrough == 0
            && !ledger.chunks.contains { $0.state == .transcribed }
        let firstHeld = ledger.chunks.first?.index ?? ((ledger.lastIndex ?? -1) + 1)
        guard saved > ledger.transcribedThrough || (startsOver && firstHeld > 0) else { return ledger }
        let chunks = ledger.chunks.filter { $0.state == .received }.map {
            WatchAudioChunk(index: $0.index, url: watchInbox.chunkURL(recordingID: ledger.recordingID, index: $0.index),
                            startOffset: $0.effectiveOffset, duration: $0.effectiveDuration)
        }
        _ = try retainWatchAudio(chunks, ledger: ledger, recordID: record.id)
        let updated = try markWatchTranscribed(ledger.recordingID, through: saved,
                                                settleBelow: startsOver ? firstHeld : nil)
        return updated ?? ledger
    }

    /// Where the saved Apple Watch lines of this conversation end, if it has any.
    private func savedWatchLinesEnd(_ recordID: String) -> TimeInterval? {
        history.first { $0.id == recordID }?.segments?
            .filter(Self.isWatchLine).map(\.end).max()
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

    /// Adds lines and/or a note to a watch conversation where it lives now: through the live
    /// session when it is the open conversation (so nothing typed there is lost), otherwise in the
    /// archive. Throws unless the change is saved.
    private func updateWatchRecord(_ recordID: String, segments added: [TranscriptSegment] = [], note: String? = nil,
                                   complete: Bool = false) throws {
        // Apple Watch files are transcribed in the transcription language (issue #206).
        if recordID == id {
            for language in Set(added.compactMap(\.language)) { noteConversationLanguage(language) }
            segments.append(contentsOf: added)
            if let note { notes = Self.appendingLine(note, to: notes) }
            guard save(announce: false) else { throw WatchConversationUnavailable() }
            return
        }
        guard let record = history.first(where: { $0.id == recordID }) else { throw WatchConversationUnavailable() }
        let lines = (record.segments ?? []) + added
        let updated = SessionRecord(id: record.id, title: record.title, date: record.date,
                                    transcript: Self.transcriptText(for: lines), summary: record.summary,
                                    segments: lines, notes: note.map { Self.appendingLine($0, to: record.notes ?? "") }
                                        ?? record.notes,
                                    quickSuggestion: record.quickSuggestion, deepAnswer: record.deepAnswer,
                                    isComplete: complete, attachments: record.attachments,
                                    sourceImportID: record.sourceImportID, titleState: record.titleState,
                                    language: record.language, languages: record.languages,
                                    selectionSummaries: record.selectionSummaries, summaryInstructions: record.summaryInstructions,
                      vocabularyDomainIDs: record.vocabularyDomainIDs, situationGrid: record.situationGrid)
        let languaged = added.compactMap(\.language).reduce(updated) { $0.recording(language: $1) }
        try archive.save(languaged)
        remember(languaged)
        exportToVault(languaged)   // Save to folder (#53)
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

/// Lines heard but not yet saved during one transcription pass.
@MainActor
private final class WatchLineBuffer {
    var lines: [TranscriptSegment] = []
    var lastSave = Date()
    /// Recording time through which lines are saved.
    var coveredThrough: TimeInterval
    let chunkEnds: [TimeInterval]

    init(coveredThrough: TimeInterval, chunkEnds: [TimeInterval]) {
        self.coveredThrough = coveredThrough
        self.chunkEnds = chunkEnds
    }

    func shouldSave(after line: TranscriptSegment) -> Bool {
        if lines.count >= MobileSession.watchLinesPerSave
            || Date().timeIntervalSince(lastSave) >= MobileSession.watchSaveInterval { return true }
        // The line reaches the end of a chunk not yet covered: saving now lets that audio go.
        return chunkEnds.contains { $0 > coveredThrough + 0.05 && line.end + 0.05 >= $0 }
    }
}
