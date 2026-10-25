import XCTest
@testable import ListenToMeCore

final class ConversationRetranscriptionTests: XCTestCase {
    private let original = TranscriptSegment(source: .you, text: "Original", isFinal: true, start: 0, end: 1)
    private let revised = TranscriptSegment(source: .you, text: "Revised", isFinal: true, start: 0, end: 1, language: "fr-FR")

    func testReplacementPreservesCurrentMetadataAndRejectsChangedTranscript() throws {
        let record = SessionRecord(id: "one", title: "Meeting", date: Date(), transcript: "You: Original", summary: "Summary",
                                   segments: [original], notes: "Notes", quickSuggestion: "Quick", deepAnswer: "Deep",
                                   summaryInstructions: "Decisions first", vocabularyDomainIDs: ["medical"])
        let preview = try ConversationRetranscription(original: record, segments: [revised], language: "fr-FR")
        let result = try preview.applying(to: record.retitled("Renamed", state: .user))
        XCTAssertEqual(result.title, "Renamed")
        XCTAssertEqual(result.segments, [revised])
        XCTAssertEqual(result.notes, "Notes")
        XCTAssertEqual(result.summary, "Summary")
        XCTAssertEqual(result.quickSuggestion, "Quick")
        XCTAssertEqual(result.deepAnswer, "Deep")
        XCTAssertEqual(result.summaryInstructions, "Decisions first")
        XCTAssertEqual(result.vocabularyDomainIDs, ["medical"])
        XCTAssertEqual(result.language, "fr-FR")
        XCTAssertEqual(result.languages, ["fr-FR"])
        XCTAssertThrowsError(try preview.applying(to: result))
        XCTAssertThrowsError(try ConversationRetranscription(original: record, segments: [], language: "en-US"))
    }

    func testWatchTimelineAndReplacementKeepDeviceButClearInferredSpeaker() throws {
        let run = SavedAudioRun(index: 2, source: .you, fileName: "watch.m4a", startedAt: Date(),
            timelineOffset: 45, timesMatchAudio: true, duration: 10, deviceName: "Apple Watch")
        let normalized = try XCTUnwrap(ConversationRetranscription.timeline(for: [run]).first)
        XCTAssertEqual(normalized.deviceName, "Apple Watch")
        XCTAssertEqual(normalized.title(partCount: 1), "Apple Watch")
        let line = TranscriptSegment(source: .you, text: "Hello", isFinal: true, start: 2, end: 4,
                                     speakerID: "watch:old:1", speakerName: "Alex")
        let placed = try XCTUnwrap(ConversationRetranscription.placing([line], run: normalized, language: "en-US").first)
        XCTAssertEqual(placed.speakerName, "Apple Watch")
        XCTAssertNil(placed.speakerID)
        XCTAssertEqual(placed.start, 47)
        XCTAssertEqual(placed.end, 49)
    }

    func testPlacesTracksOnTheirOwnTimelineAndClearsOldSpeakerIdentity() throws {
        let run = SavedAudioRun(index: 2, source: .others, fileName: "part-002-system.m4a", startedAt: Date(),
                                timelineOffset: 45, timesMatchAudio: true, duration: 10)
        let line = TranscriptSegment(source: .you, text: "Hello", isFinal: true, start: 2, end: 4,
                                     speakerID: "old", speakerName: "Old name")
        let placed = try XCTUnwrap(ConversationRetranscription.placing([line], run: run, language: "en-US").first)
        XCTAssertEqual(placed.source, .others)
        XCTAssertEqual(placed.start, 47)
        XCTAssertEqual(placed.end, 49)
        XCTAssertEqual(placed.language, "en-US")
        XCTAssertNil(placed.speakerName)
        XCTAssertNil(placed.speakerID)
        let invalid = TranscriptSegment(source: .you, text: "Bad", isFinal: true, start: .nan, end: 1)
        XCTAssertThrowsError(try ConversationRetranscription.placing([invalid], run: run, language: "en-US"))
    }
}
