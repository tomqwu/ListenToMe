import XCTest
@testable import ListenToMeCore

@MainActor
final class AudioImportFailureTests: XCTestCase {
    func testIncompleteImportSurvivesArchiveRoundTripAndRecordEdits() throws {
        let original = SessionRecord(id: "partial", title: "Import", date: Date(), transcript: "", summary: "",
                                     segments: [], isComplete: false, hasIncompleteImport: true)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(original))
        let edited = decoded.retitled("Renamed", state: .init(source: .user)).recording(language: "en")
        XCTAssertEqual(edited.hasIncompleteImport, true)
        XCTAssertEqual(edited.isComplete, false)
        let model = MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
                                   makeCapture: { MockCapture() }, makeTranscriber: { EchoTranscriber() },
                                   makeProvider: { MockLLMProvider(id: $0, deltas: []) }, models: [:])
        XCTAssertTrue(model.restoreConversation(edited))
        XCTAssertTrue(model.hasIncompleteImport)
        let legacy = SessionRecord(id: "old", title: "Old", date: Date(), transcript: "", summary: "", segments: [])
        let legacyData = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(decoding: legacyData, as: UTF8.self).contains("hasIncompleteImport"))
        XCTAssertTrue(model.restoreConversation(try JSONDecoder().decode(SessionRecord.self, from: legacyData)))
        XCTAssertFalse(model.hasIncompleteImport)
    }

    func testReadFailurePreservesPartialTranscriptAndMarksItIncomplete() async {
        let reader = FailingAudioReader()
        let store = ConversationStore()
        let model = MeetingSession(store: store, context: ContextEngine(debounce: 0),
                                   makeCapture: { MockCapture() }, makeTranscriber: { EchoTranscriber() },
                                   makeProvider: { MockLLMProvider(id: $0, deltas: []) }, models: [:])
        await model.transcribeAudio(nextChunk: { try await reader.next() })
        XCTAssertEqual(store.utterances.count, 1)
        XCTAssertFalse(model.isTranscribingFile)
        XCTAssertTrue(model.hasIncompleteImport)
        XCTAssertTrue(model.transcriptionStatus.contains("Import stopped early"))
        XCTAssertTrue(model.transcriptionStatus.contains("damaged frame"))
        await model.transcribeAudio(nextChunk: { nil })
        XCTAssertTrue(model.hasIncompleteImport, "A later import cannot repair missing audio from an earlier file")
        model.resetConversation()
        XCTAssertFalse(model.hasIncompleteImport)
    }
}

private actor FailingAudioReader {
    private var read = false
    func next() throws -> AudioChunk? {
        if read { throw QuickSummaryError.message("damaged frame") }
        read = true
        return AudioChunk(samples: [0.1], sampleRate: 16_000, source: .others, timestamp: 0)
    }
}
