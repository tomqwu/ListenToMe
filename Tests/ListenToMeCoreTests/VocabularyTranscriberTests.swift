import XCTest
@testable import ListenToMeCore

/// The session hands the active vocabularies' contextual strings to the transcriber (issue #222).
/// No real recognition runs: a fake transcriber records every context it receives.
@MainActor
final class VocabularyTranscriberTests: XCTestCase {
    private final class ContextRecordingTranscriber: Transcribing, @unchecked Sendable {
        let segments: AsyncStream<TranscriptSegment>
        private let continuation: AsyncStream<TranscriptSegment>.Continuation
        private let lock = NSLock()
        private var _received: [[String]] = []
        private var _preparedWith: [String]?
        var received: [[String]] { lock.withLock { _received } }
        /// The strings in effect when `prepare()` ran, i.e. when a real engine builds its analyzer.
        var preparedWith: [String]? { lock.withLock { _preparedWith } }

        init() { (segments, continuation) = AsyncStream<TranscriptSegment>.makeStream() }
        func setContextualStrings(_ strings: [String]) async { lock.withLock { _received.append(strings) } }
        func prepare() async { lock.withLock { _preparedWith = _received.last ?? [] } }
        func feed(_ chunk: AudioChunk) async {
            continuation.yield(TranscriptSegment(source: chunk.source, text: "seg", isFinal: true,
                                                 start: chunk.timestamp, end: chunk.timestamp))
        }
        func finish() async { continuation.finish() }
    }

    private func makeSession(_ transcriber: ContextRecordingTranscriber) -> MeetingSession {
        MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 5),
                       makeCapture: { MockCapture() }, makeTranscriber: { transcriber },
                       makeProvider: { MockLLMProvider(id: $0, deltas: ["ok"]) },
                       models: [.listener: "L", .quick: "Q", .deep: "D"])
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func testTheTranscriberHasTheVocabularyBeforeItPrepares() async throws {
        let transcriber = ContextRecordingTranscriber()
        let session = makeSession(transcriber)
        let terms = ActiveVocabulary(domains: [VocabularyCatalog.bundled.domain(id: "medical")!], myTerms: ["Acme"])
            .recognitionTerms()
        session.contextualStrings = terms
        try await session.start()
        XCTAssertEqual(transcriber.preparedWith, terms)
        XCTAssertEqual(terms.count, 100)
        XCTAssertEqual(terms.first, "Acme")
        await session.stopAndWait()
    }

    func testAnAddWhileRecordingReachesTheRunningTranscriberWithoutARestart() async throws {
        let transcriber = ContextRecordingTranscriber()
        let session = makeSession(transcriber)
        try await session.start()
        XCTAssertEqual(transcriber.received, [[]])
        session.contextualStrings = ["Kubernetes", "Terraform"]
        await waitUntil { transcriber.received.count == 2 }
        XCTAssertEqual(transcriber.received.last, ["Kubernetes", "Terraform"])
        session.contextualStrings = ["Kubernetes", "Terraform"]   // unchanged: nothing more is sent
        await Task.yield()
        XCTAssertEqual(transcriber.received.count, 2)
        XCTAssertTrue(session.isRunning)
        await session.stopAndWait()
    }

    func testImportedAudioIsTranscribedWithTheVocabularyToo() async {
        let transcriber = ContextRecordingTranscriber()
        let session = makeSession(transcriber)
        session.contextualStrings = ["voir dire"]
        let producer = ArrayChunkProducer([AudioChunk(samples: [0], sampleRate: 16_000, source: .others, timestamp: 0)])
        await session.transcribeAudio(nextChunk: { await producer.next() })
        XCTAssertEqual(transcriber.preparedWith, ["voir dire"])
    }

    func testEnginesWithoutContextualStringsIgnoreThem() async {
        let echo = EchoTranscriber()
        await echo.setContextualStrings(["ignored"])   // the protocol's default: no effect, no crash
        await echo.finish()
    }
}
