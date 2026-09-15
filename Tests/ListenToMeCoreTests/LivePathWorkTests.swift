import XCTest
@testable import ListenToMeCore

/// Issue #116: the macOS live path must not do O(transcript) work several times per partial.
/// Every ingested hypothesis runs `handleLiveEvent`, which used to rebuild the labeled piece
/// snapshot three times, join it into a string and have the review coordinator re-normalize and
/// prefix-scan the whole source — all on the main actor, several times a second, for hours.
@MainActor
final class LivePathWorkTests: XCTestCase {

    private func makeSession() -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            clock: { 0 }
        )
        return (session, store)
    }

    func testEachIngestComputesThePieceSnapshotOnce() async {
        let (session, _) = makeSession()
        session.autoSummaryEnabled = true
        let baseline = session.livePieceComputations
        for index in 0..<5 {
            await session.ingest(TranscriptSegment(source: .others, text: "Line number \(index) of speech.",
                                                   isFinal: true, start: 0, end: 1))
        }
        XCTAssertEqual(session.livePieceComputations - baseline, 5,
                       "One ingest must rebuild the labeled snapshot exactly once.")
    }

    func testReadingLiveStateWithoutNewSpeechRebuildsNothing() async {
        let (session, store) = makeSession()
        await session.ingest(TranscriptSegment(source: .others, text: "A finalized line of speech.",
                                               isFinal: true, start: 0, end: 1))
        let baseline = session.livePieceComputations
        for _ in 0..<5 { _ = session.livePiecesForTesting }
        _ = session.autoQuickStatus
        _ = session.automaticReviewStatus(.summary)
        XCTAssertEqual(session.livePieceComputations, baseline,
                       "Repeated reads with no new speech must reuse the memoized snapshot.")
        // A new hypothesis (no revision bump) must still invalidate the cache.
        store.apply(TranscriptSegment(source: .you, text: "A brand new volatile hypothesis here.",
                                      isFinal: false, start: 0, end: 1))
        XCTAssertFalse(session.livePiecesForTesting.isEmpty)
        XCTAssertGreaterThan(session.livePieceComputations, baseline)
        XCTAssertTrue(session.livePiecesForTesting.contains { $0.text.contains("volatile hypothesis") })
    }

    func testNotesKeystrokeInvalidatesTheSnapshotExactlyOnce() {
        let (session, _) = makeSession()
        let baseline = session.livePieceComputations
        session.notes = "One keystroke"
        XCTAssertEqual(session.livePieceComputations - baseline, 1)
    }

    func testUnchangedInputDoesNoCoordinatorWork() {
        let coordinator = AutomaticReviewCoordinator()
        let pieces = [QuickSummaryContext.Piece(id: "live:you:0", text: "You: Some speech.")]
        let source = pieces.map(\.text).joined(separator: "\n")
        func sync() {
            coordinator.synchronize(enabled: true, manualBusy: false, pieces: pieces, source: source,
                                    provider: { _ in MockLLMProvider(id: "m", deltas: []) },
                                    apply: { _, _, _ in })
        }
        sync()
        let baseline = coordinator.synchronizedInputs
        sync()
        sync()
        XCTAssertEqual(coordinator.synchronizedInputs, baseline,
                       "Identical pieces and source must skip normalization and the prefix scan.")
        coordinator.synchronize(enabled: true, manualBusy: false,
                                pieces: pieces + [.init(id: "live:you:1", text: "You: More.")],
                                source: source + "\nYou: More.",
                                provider: { _ in MockLLMProvider(id: "m", deltas: []) },
                                apply: { _, _, _ in })
        XCTAssertEqual(coordinator.synchronizedInputs, baseline + 1)
    }

    // MARK: - Checkpoint dirty key (issue #116, part 2)

    func testCheckpointKeyIsUnchangedUntilRevisionOrOutputsChange() {
        let key = SessionCheckpointKey(revision: 3, title: "Standup", summary: "S", notes: "N",
                                       quickSuggestion: "Q", deepAnswer: "D", complete: false)
        XCTAssertEqual(key, SessionCheckpointKey(revision: 3, title: "Standup", summary: "S", notes: "N",
                                                 quickSuggestion: "Q", deepAnswer: "D", complete: false))
        XCTAssertNotEqual(key, SessionCheckpointKey(revision: 4, title: "Standup", summary: "S", notes: "N",
                                                   quickSuggestion: "Q", deepAnswer: "D", complete: false))
        XCTAssertNotEqual(key, SessionCheckpointKey(revision: 3, title: "Standup", summary: "S2", notes: "N",
                                                   quickSuggestion: "Q", deepAnswer: "D", complete: false))
        XCTAssertNotEqual(key, SessionCheckpointKey(revision: 3, title: "Standup", summary: "S", notes: "N",
                                                   quickSuggestion: "Q", deepAnswer: "D", complete: true))
    }

    func testStoreMaintainsCountsIncrementally() {
        let store = ConversationStore()
        XCTAssertEqual(store.youCount, 0)
        XCTAssertEqual(store.othersCount, 0)
        XCTAssertEqual(store.transcriptCharacterCount, 0)
        store.apply(TranscriptSegment(source: .you, text: "12345", isFinal: true, start: 0, end: 1))
        store.apply(TranscriptSegment(source: .others, text: "123", isFinal: true, start: 0, end: 1))
        store.apply(TranscriptSegment(source: .others, text: "partial", isFinal: false, start: 0, end: 1))
        XCTAssertEqual(store.youCount, 1)
        XCTAssertEqual(store.othersCount, 1)
        XCTAssertEqual(store.transcriptCharacterCount, 8)
        store.restore([TranscriptSegment(source: .you, text: "abc", isFinal: true, start: 0, end: 1)])
        XCTAssertEqual(store.youCount, 1)
        XCTAssertEqual(store.othersCount, 0)
        XCTAssertEqual(store.transcriptCharacterCount, 3)
        store.reset()
        XCTAssertEqual(store.youCount, 0)
        XCTAssertEqual(store.othersCount, 0)
        XCTAssertEqual(store.transcriptCharacterCount, 0)
    }
}
