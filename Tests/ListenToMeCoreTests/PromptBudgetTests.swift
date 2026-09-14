import XCTest
@testable import ListenToMeCore

/// Issue #119: providers with a small context window (Apple Intelligence) must never be handed a
/// 100k-character prompt. Providers without a declared window (Ollama) keep their old budgets.
final class PromptBudgetTests: XCTestCase {

    func testUnlimitedProviderKeepsRequestedBudgetsUnchanged() {
        let allocation = PromptBudget.allocate(limit: nil, transcript: 100_000, references: 16_000)
        XCTAssertEqual(allocation.transcript, 100_000)
        XCTAssertEqual(allocation.references, 16_000)
    }

    func testAppleWindowMatchesTheCapAlreadyUsedOniOS() {
        XCTAssertEqual(PromptBudget.appleIntelligenceCharacters, 8_000)
    }

    func testLimitedProviderKeepsTranscriptPlusReferencesInsideTheWindow() {
        let limit = PromptBudget.appleIntelligenceCharacters
        let allocation = PromptBudget.allocate(limit: limit, transcript: 100_000, references: 16_000)
        XCTAssertLessThanOrEqual(allocation.transcript + allocation.references + PromptBudget.overheadReserve, limit)
        XCTAssertGreaterThan(allocation.transcript, 0)
        XCTAssertGreaterThan(allocation.references, 0)
    }

    func testReferencesNeverCrowdOutTheTranscript() {
        let allocation = PromptBudget.allocate(limit: 8_000, transcript: 100_000, references: 1_000_000)
        XCTAssertGreaterThan(allocation.transcript, allocation.references)
    }

    func testSmallReferenceAttachmentLeavesTheRestToTheTranscript() {
        let allocation = PromptBudget.allocate(limit: 8_000, transcript: 100_000, references: 120)
        XCTAssertEqual(allocation.references, 120)
        XCTAssertLessThanOrEqual(allocation.transcript + 120 + PromptBudget.overheadReserve, 8_000)
    }

    func testAllocationNeverExceedsWhatTheCallerAskedFor() {
        let allocation = PromptBudget.allocate(limit: 8_000, transcript: 400, references: 50)
        XCTAssertEqual(allocation.transcript, 400)
        XCTAssertEqual(allocation.references, 50)
    }

    func testTinyWindowStillLeavesRoomForSomeTranscript() {
        let allocation = PromptBudget.allocate(limit: 100, transcript: 100_000, references: 5_000)
        XCTAssertGreaterThan(allocation.transcript, 0)
    }
}
