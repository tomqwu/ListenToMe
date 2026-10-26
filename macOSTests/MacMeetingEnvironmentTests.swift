import XCTest
import ListenToMeCore

@MainActor
final class MacMeetingEnvironmentTests: XCTestCase {
    func testSessionAndWorkspaceShareOneStoreAndIndependentChannelBuffers() async {
        var constructions = 0
        let environment = MacMeetingEnvironment { store, others, microphone in
            constructions += 1
            XCTAssertFalse(others === microphone)
            return makeSession(store)
        }
        environment.store.apply(.init(source: .others, text: "Current conversation", isFinal: true, start: 0, end: 1))
        XCTAssertTrue(environment.store === environment.session.store)
        XCTAssertEqual(environment.session.store.utterances.first?.text, "Current conversation")
        environment.othersSink.append(samples: [0.1], sampleRate: 16_000, timestamp: 2,
                                      generation: environment.othersSink.currentGeneration())
        XCTAssertEqual(environment.othersSink.sampleCount, 1)
        XCTAssertEqual(environment.microphoneSink.sampleCount, 0)
        await environment.session.requestQuick(.answerQuestion).value
        XCTAssertEqual(environment.session.quickSuggestion, "Native graph answer")
        XCTAssertEqual(constructions, 1)
    }

    func testAnotherEnvironmentCannotReplaceTheExistingConversation() {
        let first = MacMeetingEnvironment { store, _, _ in makeSession(store) }
        first.session.notes = "Keep this context"
        first.store.apply(.init(source: .you, text: "Keep this transcript", isFinal: true, start: 0, end: 1))
        let second = MacMeetingEnvironment { store, _, _ in makeSession(store) }
        XCTAssertFalse(first.store === second.store)
        XCTAssertFalse(first.session === second.session)
        XCTAssertFalse(first.othersSink === second.othersSink)
        XCTAssertFalse(first.microphoneSink === second.microphoneSink)
        XCTAssertTrue(second.store.utterances.isEmpty)
        XCTAssertEqual(first.session.notes, "Keep this context")
        XCTAssertEqual(first.store.utterances.first?.text, "Keep this transcript")
    }

    private func makeSession(_ store: ConversationStore) -> MeetingSession {
        MeetingSession(store: store, context: ContextEngine(debounce: 8),
                       makeCapture: { EnvironmentCapture() }, makeTranscriber: { EnvironmentTranscriber() },
                       makeProvider: { _ in EnvironmentProvider() },
                       models: [.listener: "Test", .quick: "Test", .deep: "Test"])
    }
}

private struct EnvironmentCapture: AudioCapturing {
    var chunks: AsyncStream<AudioChunk> { AsyncStream { $0.finish() } }
    func start() async throws {}
    func stop() {}
}
private struct EnvironmentTranscriber: Transcribing {
    var segments: AsyncStream<TranscriptSegment> { AsyncStream { $0.finish() } }
    func feed(_ chunk: AudioChunk) async {}
    func finish() async {}
}
private struct EnvironmentProvider: LLMProvider {
    let id = "native-graph-test"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield("Native graph answer"); $0.finish() }
    }
}
