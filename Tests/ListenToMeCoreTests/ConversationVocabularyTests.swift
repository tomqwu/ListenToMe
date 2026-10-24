import XCTest
@testable import ListenToMeCore

final class ConversationVocabularyTests: XCTestCase {
    func testVocabularySurvivesArchiveTransformationsAndExport() throws {
        let record = SessionRecord(id: "conversation", title: "Plan", date: Date(), transcript: "", summary: "",
                                   summaryInstructions: "List decisions", vocabularyDomainIDs: ["medical"])
        let restored = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.vocabularyDomainIDs, ["medical"])
        XCTAssertEqual(restored.retitled("New", state: .placeholder).vocabularyDomainIDs, ["medical"])
        XCTAssertEqual(restored.with(languages: ConversationLanguages(current: "zh-Hans")).vocabularyDomainIDs,
                       ["medical"])
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(SessionExporter.json(for: record).utf8))
                                    as? [String: Any])
        XCTAssertEqual(exported["vocabularyDomainIDs"] as? [String], ["medical"])
        XCTAssertEqual(exported["summaryInstructions"] as? String, "List decisions")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        old.removeValue(forKey: "vocabularyDomainIDs")
        XCTAssertNil(try JSONDecoder().decode(SessionRecord.self,
            from: JSONSerialization.data(withJSONObject: old)).vocabularyDomainIDs)
    }

    func testAutomaticQuickAddsBoundedGuidanceWithoutChangingItsInputContract() throws {
        let context = QuickSummaryContext()
        let pieces = [QuickSummaryContext.Piece(id: "line", text: "Discuss apixaban with Dr. Okafor.")]
        let baseline = try XCTUnwrap(context.batch(pieces, summary: ""))
        let guidance = "Domain: Medical. Glossary: Dr. Okafor. " + String(repeating: "x", count: 2_000)
        let custom = try XCTUnwrap(context.batch(pieces, summary: "", personaGuidance: guidance))
        XCTAssertTrue(custom.request.system.hasPrefix(baseline.request.system))
        XCTAssertTrue(custom.request.system.contains("Domain: Medical. Glossary: Dr. Okafor."))
        XCTAssertLessThanOrEqual(custom.request.system.count - baseline.request.system.count,
                                 VocabularyPrompt.guidanceCharacterLimit + 30)
        let baselineJSON = try JSONSerialization.jsonObject(with: Data(baseline.request.messages[0].content.utf8))
        let customJSON = try JSONSerialization.jsonObject(with: Data(custom.request.messages[0].content.utf8))
        XCTAssertEqual(baselineJSON as? NSDictionary, customJSON as? NSDictionary)
    }
}
