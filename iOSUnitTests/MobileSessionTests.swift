import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileSessionTests: XCTestCase {
    func testOutputsPersistIndependentlyAndDeleteActiveDoesNotResurrect() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root)
        session.notes = "First meeting"
        session.summary = "Full summary"
        session.quickSummary = "Quick points"
        session.deepThought = "Risks and alternatives"
        XCTAssertTrue(session.save())
        let first = try XCTUnwrap(session.history.first)
        let reloaded = MobileSession(storageDirectory: root)
        XCTAssertEqual(reloaded.output(for: .summary), "Full summary")
        XCTAssertEqual(reloaded.output(for: .quick), "Quick points")
        XCTAssertEqual(reloaded.output(for: .deep), "Risks and alternatives")
        XCTAssertTrue(reloaded.markdown.contains("Quick points"))
        XCTAssertTrue(reloaded.markdown.contains("Risks and alternatives"))
        session.newConversation()
        XCTAssertEqual(session.quickSummary, "")
        session.notes = "Second meeting"
        session.save()
        let second = try XCTUnwrap(session.history.first(where: { $0.id != first.id }))
        session.deleteConversation(id: first.id)
        XCTAssertEqual(session.notes, "Second meeting")
        XCTAssertEqual(session.history.map(\.id), [second.id])
        session.deleteConversation(id: second.id)
        XCTAssertFalse(session.hasContent)
        XCTAssertTrue(session.history.isEmpty)
        let afterDelete = MobileSession(storageDirectory: root)
        XCTAssertFalse(afterDelete.hasContent)
        XCTAssertTrue(afterDelete.history.isEmpty)
        afterDelete.save()
        XCTAssertTrue(afterDelete.history.isEmpty)
    }

    func testRoleModelsPersistAndMissingRoleDoesNotDisableOtherRoles() {
        let settings = MobileAISettings()
        let original = MobileSummaryMode.allCases.map { settings.selectedModel(for: $0) }
        defer {
            for (mode, model) in zip(MobileSummaryMode.allCases, original) { settings.selectModel(model, for: mode) }
        }
        settings.selectModel("summary-model", for: .summary)
        settings.selectModel("quick-model", for: .quick)
        settings.selectModel("deep-model", for: .deep)
        let restored = MobileAISettings()
        XCTAssertEqual(restored.selectedModel(for: .summary), "summary-model")
        XCTAssertEqual(restored.selectedModel(for: .quick), "quick-model")
        XCTAssertEqual(restored.selectedModel(for: .deep), "deep-model")
        restored.hasKey = true
        restored.models = [.init(name: "summary-model"), .init(name: "quick-model")]
        XCTAssertNil(restored.availability(for: .quick))
        XCTAssertNotNil(restored.availability(for: .deep))
        XCTAssertTrue(MobileSummaryMode.quick.instructions.contains("five"))
        XCTAssertTrue(MobileSummaryMode.deep.instructions.contains("tradeoffs"))
    }
}
