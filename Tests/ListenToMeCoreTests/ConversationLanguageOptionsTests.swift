import XCTest
@testable import ListenToMeCore

final class ConversationLanguageOptionsTests: XCTestCase {
    @MainActor
    func testMacRestorationRefreshesTranslationInputsAndNewClearsDerivedText() async {
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { fatalError("Text-only") }, makeTranscriber: { fatalError("Text-only") },
            makeProvider: { _ in fatalError("No AI translation") }, models: [:])
        let options = ConversationLanguageOptions(translationTarget: "es", summaryTranslationTarget: "fr")
        let record = SessionRecord(id: "a", title: "Saved", date: Date(), transcript: "", summary: "Saved summary.",
                                   segments: [], languageOptions: options)
        XCTAssertTrue(session.restoreConversation(record))
        XCTAssertEqual(session.summaryTranslation.source, "Saved summary.")
        XCTAssertEqual(session.summaryTranslation.targetLanguage, "fr")
        XCTAssertFalse(session.summaryTranslation.isRequested)
        session.resetConversation()
        XCTAssertEqual(session.summaryTranslation.source, "")
        XCTAssertEqual(session.languageOptions, .init())
    }
    func testChangingOnlyTranslationChoicesMakesCheckpointDirty() {
        func key(_ options: ConversationLanguageOptions) -> SessionCheckpointKey {
            .init(revision: 1, title: "Same", summary: "Original", notes: "", quickSuggestion: "", deepAnswer: "",
                  complete: true, languageOptions: options)
        }
        let unchanged = key(.init())
        XCTAssertNotEqual(unchanged, key(.init(translateTranscript: true)))
        XCTAssertNotEqual(unchanged, key(.init(translationTarget: "fr")))
        XCTAssertNotEqual(unchanged, key(.init(summaryTranslationTarget: "ja")))
        XCTAssertEqual(unchanged, key(.init()))
    }
    func testLanguageChoicesSurviveArchiveWithoutChangingOriginalSpeech() throws {
        let original = SessionRecord(id: "conversation", title: "Planning", date: Date(timeIntervalSince1970: 1),
            transcript: "You: The meeting starts tomorrow.", summary: "Previous summary.",
            segments: [.init(source: .you, text: "The meeting starts tomorrow.", isFinal: true,
                             start: 0, end: 3, language: "en-US")])
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["languageOptions"] = ["translateTranscript": true, "translationTarget": "fr", "summaryTranslationTarget": "zh-Hant"]
        let loaded = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
        let options = try XCTUnwrap(roundTrip["languageOptions"] as? [String: Any],
                                   "Reopening must keep the conversation's independent translation/summary choices")
        XCTAssertEqual(options["translationTarget"] as? String, "fr")
        XCTAssertEqual(options["summaryTranslationTarget"] as? String, "zh-Hant")
        XCTAssertEqual(options["translateTranscript"] as? Bool, true)
        XCTAssertEqual(loaded.segments, original.segments)
        XCTAssertEqual(loaded.transcript, original.transcript)
        XCTAssertEqual(loaded.summary, original.summary)
        let renamed = loaded.retitled("Renamed", state: .user)
        let relabeled = loaded.with(languages: .init(current: "en", all: ["en"]))
        let retranscribed = try ConversationRetranscription(original: loaded,
            segments: [.init(source: .you, text: "The meeting starts tomorrow.", isFinal: true,
                             start: 0, end: 3, language: "en")], language: "en").applying(to: loaded)
        for transformed in [renamed, relabeled, retranscribed] {
            XCTAssertEqual(transformed.languageOptions, loaded.languageOptions)
        }
        XCTAssertNil(original.languageOptions, "Older archives retain their previous default behavior")
    }
}
