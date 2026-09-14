import FoundationModels
import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

/// Stands in for the on-device transport so the simulator can exercise the Apple Intelligence path.
private final class RecordingOnDeviceProvider: LLMProvider, @unchecked Sendable {
    let id = "on-device-test"
    var response: String
    var failure: (any Error)?
    private(set) var request: LLMRequest?
    init(response: String, failure: (any Error)? = nil) { self.response = response; self.failure = failure }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        self.request = request
        let response = response, failure = failure
        return AsyncThrowingStream { continuation in
            if let failure { continuation.finish(throwing: failure) } else {
                continuation.yield(response); continuation.finish()
            }
        }
    }
}

@MainActor
final class MobileAppleIntelligenceTests: XCTestCase {
    /// #123: manual Quick on Apple Intelligence used to send the evaluator's JSON envelope to the
    /// on-device model and then demand an exact JSON shape back. It now asks for prose bullets.
    func testAppleManualQuickAsksForProseBulletsAndPublishesThem() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = RecordingOnDeviceProvider(
            response: "Key takeaways:\n- Sarah owns the rollout.\n- Budget is open.")
        let session = MobileSession(storageDirectory: root)
        session.onDeviceProviderOverride = provider
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .apple
        session.notes = "Sarah will own the rollout; the budget is unresolved."

        XCTAssertNil(session.summaryAvailability(for: .quick), "A stubbed on-device model is available")
        await session.summarize(mode: .quick)

        XCTAssertNil(session.message, session.message ?? "")
        XCTAssertNil(session.quickSummaryError)
        XCTAssertEqual(session.quickSummary, "- Sarah owns the rollout.\n- Budget is open.")
        let request = try XCTUnwrap(provider.request)
        XCTAssertEqual(request.system, MobileQuickContext.manualProseInstructions)
        XCTAssertFalse(request.system.contains("JSON"), "The on-device model is never asked for JSON")
        XCTAssertEqual(request.messages.first?.content, session.summarySource)
        XCTAssertNotEqual(request.purpose, .quickEvaluation,
                          "The automatic evaluator purpose stays refused on the Apple path")
        // Prose that carries no takeaway still leaves a readable pane rather than a parser error.
        provider.response = "No key takeaway yet."
        await session.summarize(mode: .quick)
        XCTAssertNil(session.quickSummaryError)
        XCTAssertEqual(session.quickSummary, "No key takeaway yet.")
    }

    /// #123: an unsupported conversation language used to fail only at generation time. The gate is
    /// per conversation — the device's UI locale must never decide whether the provider is available.
    func testUnsupportedConversationLanguageIsReportedWithoutDisablingTheProvider() {
        let cantonese = Locale(identifier: "yue-HK")
        let english = Locale(identifier: "en-US")
        XCTAssertNil(AppleIntelligenceProvider.unsupportedLocaleReason(for: cantonese, isSupported: { _ in true }))
        let reason = AppleIntelligenceProvider.unsupportedLocaleReason(for: cantonese, isSupported: { $0 == english })
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("Ollama") == true, reason ?? "")
        XCTAssertNil(AppleIntelligenceProvider.unsupportedLocaleReason(for: english, isSupported: { $0 == english }))
        // Availability itself stays locale-free, so a fresh install's default never turns on the
        // device's UI language and the macOS status line is unchanged.
        XCTAssertEqual(MobileAISettings.defaultProviderReason, AppleIntelligenceProvider.unavailableReason)
    }

    /// #123: FoundationModels generation failures reached the pane as developer-facing text.
    func testAppleGenerationFailuresBecomeMessagesAUserCanActOn() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        for failure: LanguageModelSession.GenerationError in [.exceededContextWindowSize(context),
                                                              .guardrailViolation(context),
                                                              .unsupportedLanguageOrLocale(context)] {
            let message = AppleIntelligenceProvider.message(for: failure)
            XCTAssertNotNil(message, "\(failure) must be explained")
            XCTAssertEqual(MobileAISettings.errorMessage(failure), message)
            XCTAssertFalse(message?.contains("Error Domain") == true, message ?? "")
            XCTAssertTrue(message?.contains("Ollama") == true, "Say what to do instead: \(message ?? "")")
        }
        XCTAssertNil(AppleIntelligenceProvider.message(for: URLError(.timedOut)),
                     "Only on-device generation failures are rewritten")

        let tooLong = LanguageModelSession.GenerationError.exceededContextWindowSize(context)
        let provider = RecordingOnDeviceProvider(response: "", failure: tooLong)
        let session = MobileSession(storageDirectory: root)
        session.onDeviceProviderOverride = provider
        let original = session.ai.provider
        defer { session.ai.provider = original }
        session.ai.provider = .apple
        session.notes = "A long meeting"
        session.quickSummary = "Previous takeaway"
        await session.summarize(mode: .quick)
        XCTAssertEqual(session.quickSummary, "Previous takeaway")
        XCTAssertTrue(session.message?.contains("context window") == true, session.message ?? "")
    }
}
