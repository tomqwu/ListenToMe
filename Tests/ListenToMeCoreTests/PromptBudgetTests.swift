import XCTest
@testable import ListenToMeCore

/// Issue #119: providers with a small context window (Apple Intelligence) must never be handed a
/// 100k-character prompt. Providers without a declared window (Ollama) keep their old budgets.
final class PromptBudgetTests: XCTestCase {

    private let limit = PromptBudget.appleIntelligenceCharacters

    func testUnlimitedProviderKeepsRequestedBudgetsUnchanged() {
        let allocation = PromptBudget.allocate(limit: nil, scaffold: 900, transcript: 100_000,
                                               references: 16_000, summary: 5_000, notes: 2_000)
        XCTAssertEqual(allocation.transcript, 100_000)
        XCTAssertEqual(allocation.references, 16_000)
        XCTAssertEqual(allocation.summary, 5_000)
        XCTAssertEqual(allocation.notes, 2_000)
    }

    func testAppleWindowMatchesTheCapAlreadyUsedOniOS() {
        XCTAssertEqual(PromptBudget.appleIntelligenceCharacters, 8_000)
    }

    /// Everything the prompt will contain — scaffold, transcript, references, summary, notes and
    /// room for the answer — has to fit inside the window.
    func testEveryPartOfThePromptFitsInsideTheWindow() {
        let scaffold = 1_100
        let allocation = PromptBudget.allocate(limit: limit, scaffold: scaffold, transcript: 100_000,
                                               references: 16_000, summary: 9_000, notes: 9_000)
        let total = scaffold + allocation.transcript + allocation.references
            + allocation.summary + allocation.notes + PromptBudget.answerReserve
        XCTAssertLessThanOrEqual(total, limit)
        XCTAssertGreaterThan(allocation.transcript, 0)
    }

    func testReferencesNeverCrowdOutTheTranscript() {
        let allocation = PromptBudget.allocate(limit: limit, scaffold: 800, transcript: 100_000,
                                               references: 1_000_000)
        XCTAssertGreaterThan(allocation.transcript, allocation.references)
    }

    func testSummaryAndNotesAreCappedJointlyAndCanUseEachOthersSlack() {
        let noNotes = PromptBudget.allocate(limit: limit, scaffold: 800, transcript: 100_000,
                                            references: 0, summary: 100_000, notes: 0)
        let both = PromptBudget.allocate(limit: limit, scaffold: 800, transcript: 100_000,
                                         references: 0, summary: 100_000, notes: 100_000)
        XCTAssertGreaterThan(noNotes.summary, 0)
        XCTAssertEqual(noNotes.notes, 0)
        XCTAssertEqual(both.summary + both.notes, noNotes.summary)
    }

    func testSmallAttachmentsArePassedThroughWhole() {
        let allocation = PromptBudget.allocate(limit: limit, scaffold: 900, transcript: 100_000,
                                               references: 120, summary: 40, notes: 30)
        XCTAssertEqual(allocation.references, 120)
        XCTAssertEqual(allocation.summary, 40)
        XCTAssertEqual(allocation.notes, 30)
    }

    func testAllocationNeverExceedsWhatTheCallerAskedFor() {
        let allocation = PromptBudget.allocate(limit: limit, scaffold: 900, transcript: 400,
                                               references: 50)
        XCTAssertEqual(allocation.transcript, 400)
        XCTAssertEqual(allocation.references, 50)
    }

    func testPathologicalScaffoldStillLeavesRoomForSomeTranscript() {
        let allocation = PromptBudget.allocate(limit: 100, scaffold: 50_000, transcript: 100_000,
                                               references: 5_000)
        XCTAssertGreaterThanOrEqual(allocation.transcript, 1)
    }

    // MARK: - Notice wording

    func testNoticeNamesWhatWasActuallyDropped() {
        XCTAssertNil(PromptBudget.truncationNotice(transcriptDropped: false, referencesDropped: false))
        let speech = PromptBudget.truncationNotice(transcriptDropped: true, referencesDropped: false)
        let refs = PromptBudget.truncationNotice(transcriptDropped: false, referencesDropped: true)
        let both = PromptBudget.truncationNotice(transcriptDropped: true, referencesDropped: true)
        XCTAssertTrue(speech?.contains("most recent speech") == true, speech ?? "")
        XCTAssertFalse(speech?.contains("reference") == true, speech ?? "")
        XCTAssertTrue(refs?.contains("reference") == true, refs ?? "")
        XCTAssertFalse(refs?.contains("most recent speech") == true, refs ?? "")
        XCTAssertTrue(both?.contains("reference") == true, both ?? "")
        XCTAssertTrue(both?.contains("older speech") == true, both ?? "")
    }

    /// Clamped notes / rolling summary are grounding, not speech: they must be named as themselves,
    /// never reported as "only the most recent speech is included".
    func testClampedSummaryOrNotesGetTheirOwnWording() {
        let notice = PromptBudget.truncationNotice(transcriptDropped: false, referencesDropped: false,
                                                   auxiliaryDropped: true)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.contains("notes") == true, notice ?? "")
        XCTAssertTrue(notice?.contains("running summary") == true, notice ?? "")
        XCTAssertFalse(notice?.contains("most recent speech") == true, notice ?? "")
        XCTAssertFalse(notice?.contains("older speech") == true, notice ?? "")
        XCTAssertFalse(notice?.contains("reference") == true, notice ?? "")
    }

    func testAllThreeKindsOfLossAreNamedTogether() {
        let notice = PromptBudget.truncationNotice(transcriptDropped: true, referencesDropped: true,
                                                   auxiliaryDropped: true)
        XCTAssertTrue(notice?.contains("older speech") == true, notice ?? "")
        XCTAssertTrue(notice?.contains("reference") == true, notice ?? "")
        XCTAssertTrue(notice?.contains("notes") == true, notice ?? "")
    }

    // MARK: - Transcript cost

    func testSegmentCostChargesTheSpeakerLabelAndSeparator() {
        let segment = TranscriptSegment(source: .others, text: "hi", isFinal: true, start: 0, end: 1)
        // "Others: hi" plus the joining newline.
        XCTAssertEqual(TranscriptSegment.promptCharacterCost(segment), "Others: hi\n".count)
    }
}
