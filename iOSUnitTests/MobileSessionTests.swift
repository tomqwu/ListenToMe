import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileSessionTests: XCTestCase {
    func testAutomaticQuickSummaryRunsWithoutViewRetriesFailureAndTracksNewText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = AutoSummaryProvider()
        let session = MobileSession(storageDirectory: root, summaryProvider: provider,
                                    autoInterval: .milliseconds(50))
        let originalAuto = session.autoQuick
        defer { session.state = .idle; session.autoQuick = originalAuto }
        session.autoQuick = false
        session.partial = TranscriptSegment(source: .you, text: "Review Friday.", isFinal: false, start: 0, end: 1)
        session.state = .recording
        try await Task.sleep(for: .milliseconds(100))
        let beforeOptIn = await provider.count()
        XCTAssertEqual(beforeOptIn, 0)
        session.autoQuick = true
        for _ in 0..<100 where session.quickSummary.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.quickSummary, "Quick: Review Friday.")
        let afterRetry = await provider.count()
        XCTAssertEqual(afterRetry, 2, "A failed request must retry unchanged text")
        try await Task.sleep(for: .milliseconds(120))
        let withoutChanges = await provider.count()
        XCTAssertEqual(withoutChanges, 2, "Successful unchanged input must not be resent")
        session.partial = TranscriptSegment(source: .you, text: "Review Monday.", isFinal: false, start: 0, end: 2)
        for _ in 0..<100 where session.quickSummary != "Quick: Review Monday." {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.quickSummary, "Quick: Review Monday.")
        XCTAssertEqual(session.summary, "")
        XCTAssertEqual(session.deepThought, "")
        session.autoQuick = false
        session.notes = "Do not send this."
        try await Task.sleep(for: .milliseconds(120))
        let afterDisabling = await provider.count()
        XCTAssertEqual(afterDisabling, 3)
        session.state = .idle
        session.autoQuick = true
        try await Task.sleep(for: .milliseconds(120))
        let whileIdle = await provider.count()
        XCTAssertEqual(whileIdle, 3, "Idle sessions must not auto-send")
    }

    func testSummaryReadinessAllowsRecordingAndExplainsEveryBlockedState() {
        for state in [MobileSession.State.idle, .recording] {
            XCTAssertNil(MobileSession.summaryBlockReason(state: state, generating: false,
                                                          source: "Meeting notes", providerReason: nil))
            XCTAssertEqual(MobileSession.summaryBlockReason(state: state, generating: false,
                                                            source: "Meeting notes", providerReason: "Model not ready"),
                           "Model not ready")
        }
        XCTAssertTrue(MobileSession.summaryBlockReason(state: .idle, generating: false,
                                                       source: " \n ", providerReason: nil)!.contains("Add notes"))
        XCTAssertTrue(MobileSession.summaryBlockReason(state: .recording, generating: true,
                                                       source: "Notes", providerReason: nil)!.contains("Cancel summary"))
        for state in [MobileSession.State.preparing, .stopping] {
            XCTAssertNotNil(MobileSession.summaryBlockReason(state: state, generating: false,
                                                             source: "Notes", providerReason: nil))
        }
    }

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

private actor AutoSummaryProvider: LLMProvider {
    nonisolated let id = "auto-test"
    private var requests = 0
    func count() -> Int { requests }
    private func response(_ request: LLMRequest) throws -> String {
        requests += 1
        if requests == 1 { throw URLError(.networkConnectionLost) }
        return "Quick: " + (request.messages.last?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    nonisolated func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do { continuation.yield(try await response(request)); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
        }
    }
}
