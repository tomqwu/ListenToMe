import XCTest
@testable import ListenToMeCore

/// What Share offers for one conversation and the text each choice sends.
final class ConversationShareTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_792_766_100)   // 2026-10-23 14:35:00 UTC

    private func record(summary: String = "", quick: String? = nil, transcript: String = "") -> SessionRecord {
        SessionRecord(id: "r", title: "Weekly sync", date: date, transcript: transcript, summary: summary,
                      quickSuggestion: quick)
    }

    func testOffersOnlyWhatTheConversationHas() {
        let full = record(summary: "Decisions were made.", quick: "Ship Friday.", transcript: "Hello")
        XCTAssertEqual(ConversationShare.contents(for: full, hasAudio: true),
                       [.quickSummary, .fullSummary, .conversation, .audio])
        XCTAssertEqual(ConversationShare.contents(for: record(transcript: "Hello"), hasAudio: false), [.conversation])
        XCTAssertEqual(ConversationShare.contents(for: record(summary: "  \n", quick: " "), hasAudio: false), [],
                       "blank summaries and an empty conversation offer nothing")
        XCTAssertEqual(ConversationShare.contents(for: record(), hasAudio: true), [.audio])
    }

    func testSummariesShareWithoutTheTranscript() {
        let shared = record(summary: "Decisions were made.", quick: "  Ship Friday.  ", transcript: "Secret aside")
        XCTAssertEqual(ConversationShare.text(.quickSummary, for: shared, timeZone: utc),
                       "Weekly sync\nRecorded 2026-10-23 14:35\n\nQuick summary\nShip Friday.\n")
        XCTAssertEqual(ConversationShare.text(.fullSummary, for: shared, timeZone: utc),
                       "Weekly sync\nRecorded 2026-10-23 14:35\n\nFull summary\nDecisions were made.\n")
        XCTAssertFalse(ConversationShare.text(.fullSummary, for: shared, timeZone: utc)!.contains("Secret aside"))
    }

    func testConversationSharesEverythingAndAudioAndBlanksShareNoText() {
        let shared = record(summary: "S", quick: "Q", transcript: "Hello there")
        XCTAssertEqual(ConversationShare.text(.conversation, for: shared, timeZone: utc),
                       SessionExporter.plainText(for: shared, timeZone: utc))
        XCTAssertNil(ConversationShare.text(.audio, for: shared, timeZone: utc), "audio shares files, not text")
        XCTAssertNil(ConversationShare.text(.quickSummary, for: record(quick: " "), timeZone: utc))
    }

    func testTitles() {
        XCTAssertEqual(ConversationShareContent.allCases.map(\.title),
                       ["Quick summary", "Full summary", "Whole conversation", "Audio"])
    }
}
