import XCTest
@testable import ListenToMeCore

/// What Share offers for one conversation and the text each choice sends. Share never sends the
/// transcript: only a summary or the saved audio.
final class ConversationShareTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_792_766_100)   // 2026-10-23 14:35:00 UTC

    private func record(summary: String = "", quick: String? = nil, transcript: String = "",
                        notes: String = "") -> SessionRecord {
        SessionRecord(id: "r", title: "Weekly sync", date: date, transcript: transcript, summary: summary,
                      notes: notes, quickSuggestion: quick)
    }

    func testOffersOnlyTheSummariesAndAudioTheConversationHas() {
        let full = record(summary: "Decisions were made.", quick: "Ship Friday.", transcript: "Hello")
        XCTAssertEqual(ConversationShare.contents(for: full, hasAudio: true), [.fullSummary, .quickSummary, .audio])
        XCTAssertEqual(ConversationShare.contents(for: record(transcript: "Hello", notes: "n"), hasAudio: false), [],
                       "a transcript or notes alone offer nothing to share")
        XCTAssertEqual(ConversationShare.contents(for: record(summary: "  \n", quick: " "), hasAudio: false), [],
                       "blank summaries are not offered")
        XCTAssertEqual(ConversationShare.contents(for: record(), hasAudio: true), [.audio])
    }

    func testDefaultShareIsTheSummaryNeverTheTranscript() {
        XCTAssertEqual(ConversationShare.defaultContent(for: record(summary: "Full", quick: "Quick", transcript: "Hi")),
                       .fullSummary, "the full summary is the default when there is one")
        XCTAssertEqual(ConversationShare.defaultContent(for: record(summary: " ", quick: "Quick", transcript: "Hi")),
                       .quickSummary, "otherwise the Quick summary")
        XCTAssertNil(ConversationShare.defaultContent(for: record(transcript: "Live words")),
                     "with no summary there is nothing to share by default")
    }

    func testSummariesShareWithoutTheTranscriptOrNotes() {
        let shared = record(summary: "Decisions were made.", quick: "  Ship Friday.  ", transcript: "Secret aside",
                            notes: "Private note")
        XCTAssertEqual(ConversationShare.text(.quickSummary, for: shared, timeZone: utc),
                       "Weekly sync\nRecorded 2026-10-23 14:35\n\nQuick summary\nShip Friday.\n")
        XCTAssertEqual(ConversationShare.text(.fullSummary, for: shared, timeZone: utc),
                       "Weekly sync\nRecorded 2026-10-23 14:35\n\nFull summary\nDecisions were made.\n")
        for content in ConversationShareContent.allCases {
            let text = ConversationShare.text(content, for: shared, timeZone: utc) ?? ""
            XCTAssertFalse(text.contains("Secret aside") || text.contains("Private note"), "\(content): \(text)")
        }
    }

    func testAudioAndBlankSummariesShareNoText() {
        let shared = record(summary: "S", quick: "Q", transcript: "Hello there")
        XCTAssertNil(ConversationShare.text(.audio, for: shared, timeZone: utc), "audio shares files, not text")
        XCTAssertNil(ConversationShare.text(.quickSummary, for: record(quick: " "), timeZone: utc))
    }

    func testTitles() {
        XCTAssertEqual(ConversationShareContent.allCases.map(\.title), ["Full summary", "Quick summary", "Audio"])
    }
}
