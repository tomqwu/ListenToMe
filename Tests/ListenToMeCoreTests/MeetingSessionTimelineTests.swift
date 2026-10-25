import XCTest
@testable import ListenToMeCore

/// Review of #233, finding 1: every Mac capture's engine times restart at zero (Stop → Listen in the
/// same conversation, or a language change that restarts capture). The session moves each recording's
/// timed lines past the lines already there, as iOS does, and leaves untimed lines untimed.
@MainActor
final class MeetingSessionTimelineTests: XCTestCase {
    private final class Transcribers: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [MockTranscriber] = []
        var all: [MockTranscriber] {
            get { lock.withLock { made } }
            set { lock.withLock { made = newValue } }
        }
    }

    private func makeSession() -> (MeetingSession, Transcribers) {
        let made = Transcribers()
        let session = MeetingSession(
            store: ConversationStore(), context: ContextEngine(debounce: 0),
            makeCapture: { MockCapture() },
            makeTranscriber: { let transcriber = MockTranscriber(); made.all.append(transcriber); return transcriber },
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"], clock: { 999_999 })
        session.proactiveEnabled = false
        return (session, made)
    }

    func testRestoreConversationKeepsInstructionsAndClearsThemOnReset() {
        let (session, _) = makeSession()
        let record = SessionRecord(id: "saved", title: "Planning", date: Date(), transcript: "Planning",
            summary: "A plan", segments: [TranscriptSegment(source: .you, text: "Planning", isFinal: true, start: 0, end: 1)],
            summaryInstructions: "Prioritize risks.")
        XCTAssertTrue(session.restoreConversation(record))
        XCTAssertEqual(session.summaryInstructions, "Prioritize risks.")
        XCTAssertEqual(session.listenerSummary, "A plan")
        XCTAssertTrue(session.listenerPersona?.contains("Prioritize risks.") ?? false)
        session.resetConversation()
        XCTAssertEqual(session.summaryInstructions, "")
        XCTAssertEqual(session.listenerSummary, "")
    }

    private func waitUntil(_ cond: () -> Bool) async {
        for _ in 0..<200 where !cond() { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    private func say(_ text: String, _ start: TimeInterval, _ end: TimeInterval,
                     source: SpeakerSource = .others) -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true, start: start, end: end)
    }

    func testDelayedBatchedSourcesKeepReportedRangesAndOldRunCannotLeakAfterRestart() async throws {
        let (session, made) = makeSession()
        try await session.start()
        let old = try XCTUnwrap(made.all.last)
        old.emit(say("Delayed microphone", 2, 4, source: .you))
        old.emit(say("Delayed system audio", 8, 10))
        await waitUntil { session.store.utterances.count == 2 }
        XCTAssertEqual(session.store.utterances.map(\.start), [2, 8])
        XCTAssertEqual(session.store.utterances.map(\.end), [4, 10])
        await session.stopAndWait()
        try await session.start()
        old.emit(say("Obsolete final", 100, 101))
        made.all.last?.emit(say("New run", 1, 2, source: .you))
        await waitUntil { session.store.utterances.count == 3 }
        await session.stopAndWait()
        XCTAssertEqual(session.store.utterances.map(\.text), ["Delayed microphone", "Delayed system audio", "New run"])
        XCTAssertEqual(session.store.utterances.last?.start, 11)
        XCTAssertEqual(session.store.utterances.last?.end, 12)
    }

    func testSecondRecordingContinuesTheConversationTimeline() async throws {
        let (session, made) = makeSession()
        try await session.start()
        made.all.last?.emit(say("First recording.", 1, 4))
        made.all.last?.emit(say("Still first.", 5, 30))
        await waitUntil { session.store.utterances.count == 2 }
        await session.stopAndWait()
        XCTAssertEqual(session.recordingOffset, 0)

        try await session.start()
        XCTAssertEqual(session.recordingOffset, 30, "the next recording starts where the last line ended")
        made.all.last?.emit(say("Second recording.", 1, 3))
        made.all.last?.emit(say("Untimed engine line.", 0, 0, source: .you))
        await waitUntil { session.store.utterances.count == 4 }
        await session.stopAndWait()

        let lines = session.store.utterances
        XCTAssertEqual(lines.map(\.start), [1, 5, 31, 0])
        XCTAssertEqual(lines.map(\.end), [4, 30, 33, 0], "an untimed line is never given a time")
        XCTAssertEqual(TranscriptTimestamp.recordings(lines).count, 1, "one continuous timeline")
        XCTAssertEqual(TranscriptTimestamp.duration(of: lines), 32)
        let record = SessionRecord(id: "r", title: "T", date: Date(), transcript: "", summary: "", segments: lines)
        let starts = SessionExporter.cues(for: lines).map(\.start)
        XCTAssertEqual(starts, starts.sorted(), "subtitles do not interleave the recordings")
        XCTAssertTrue(SessionExporter.markdown(for: record).contains("- [00:31] **Others:** Second recording."))

        session.resetConversation()
        XCTAssertEqual(session.recordingOffset, 0)
    }
}
