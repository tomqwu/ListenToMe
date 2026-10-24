import XCTest
@testable import ListenToMeCore

final class ConversationPromptTests: XCTestCase {
    func testInstructionsSurviveArchiveAndRecordTransformations() throws {
        let record = SessionRecord(id: "conversation", title: "Plan", date: Date(), transcript: "", summary: "",
                                   summaryInstructions: "Use Chinese and list decisions first.")
        let restored = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.summaryInstructions, record.summaryInstructions)
        XCTAssertEqual(restored.retitled("New title", state: .placeholder).summaryInstructions, record.summaryInstructions)
        XCTAssertEqual(restored.with(languages: ConversationLanguages(current: "zh-Hans")).summaryInstructions,
                       record.summaryInstructions)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "summaryInstructions")
        let old = try JSONDecoder().decode(SessionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.summaryInstructions)
    }

    func testDraftLimitsAndDomainPresets() {
        XCTAssertNil(ConversationPrompt.guidance("  \n "))
        XCTAssertEqual(ConversationPrompt.normalized(String(repeating: "字", count: 1_200)).count, 1_000)
        for domain in VocabularyCatalog.bundled.domains {
            XCTAssertFalse(ConversationPrompt.preset(domain, saved: false).isEmpty)
            XCTAssertTrue(ConversationPrompt.preset(domain, saved: true).contains(domain.summaryLayout[0]))
        }
    }

    func testAutomaticQuickCarriesInstructionsAndKeepsFormatContract() throws {
        let context = QuickSummaryContext()
        let pieces = [QuickSummaryContext.Piece(id: "line", text: "We agreed to launch on Friday.")]
        let baseline = try XCTUnwrap(context.batch(pieces, summary: ""))
        let custom = try XCTUnwrap(context.batch(pieces, summary: "", summaryInstructions: "Emphasize decisions."))
        XCTAssertTrue(custom.request.system.contains("Emphasize decisions."))
        XCTAssertTrue(custom.request.system.hasPrefix(baseline.request.system))
        let customData = try XCTUnwrap(custom.request.messages.first?.content.data(using: .utf8))
        let baselineData = try XCTUnwrap(baseline.request.messages.first?.content.data(using: .utf8))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: customData) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: baselineData) as? NSDictionary)
        XCTAssertEqual(try context.batch(pieces, summary: "", summaryInstructions: "  ")?.request.system,
                       baseline.request.system)
    }

    func testTypedQuestionIsNotTruncatedToChipLength() {
        let question = String(repeating: "Explain this decision and its evidence. ", count: 5)
        XCTAssertTrue(PromptBuilder.askInstruction(question).contains(question.trimmingCharacters(in: .whitespaces)))
    }
}
