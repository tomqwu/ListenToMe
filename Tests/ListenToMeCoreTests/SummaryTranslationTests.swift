import XCTest
@testable import ListenToMeCore

@MainActor
final class SummaryTranslationTests: XCTestCase {
    private func settle() async { for _ in 0..<300 { await Task.yield() } }
    func testSummaryPageTranslationIsExplicitAndPreservesOriginalFormattingAndCode() async {
        let service = SummaryTranslationDouble(); let translation = SummaryTranslationCoordinator(translator: service)
        let original = "# Decisions\n\n- Ship Friday.\n\n```swift\nlet ship = true\n```"
        translation.update(source: original, conversationID: "meeting", target: "fr")
        await settle()
        XCTAssertEqual(translation.source, original)
        XCTAssertEqual(service.calls, [], "Merely opening Summary never translates or downloads")
        translation.request(); await settle()
        XCTAssertEqual(translation.translatedText, "# Décisions\n\n- Livrer vendredi.\n\n```swift\nlet ship = true\n```")
        XCTAssertEqual(service.calls, ["Decisions", "Ship Friday."])
        XCTAssertEqual(translation.source, original, "The original summary remains available and authoritative")
        translation.cancel(); await settle()
        XCTAssertNil(translation.translatedText); XCTAssertEqual(translation.source, original)
    }
    func testLateSummaryCannotReplaceChangedSourceTargetOrConversationAndDraftsAreNotTranslated() async {
        for change in ["source", "target", "conversation", "draft"] {
            let service = SummaryTranslationDouble(); service.holdNext = true
            let translation = SummaryTranslationCoordinator(translator: service)
            translation.update(source: "Ship Friday.", conversationID: "a", target: "fr")
            translation.request(); await settle()
            XCTAssertEqual(service.calls, ["Ship Friday."])
            switch change {
            case "source": translation.update(source: "Decisions", conversationID: "a", target: "fr")
            case "target": translation.update(source: "Ship Friday.", conversationID: "a", target: "es")
            case "conversation": translation.update(source: "Decisions", conversationID: "b", target: "fr")
            default: translation.update(source: "A growing draft", conversationID: "a", target: "fr", isGenerating: true)
            }
            service.release(); await settle()
            switch change {
            case "source": XCTAssertEqual(translation.translatedText, "Décisions")
            case "target": XCTAssertEqual(translation.translatedText, "Entregar el viernes.")
            default: XCTAssertNil(translation.translatedText)
            }
            XCTAssertFalse(service.calls.contains("A growing draft"))
        }
    }
    func testLongerMarkdownFencesNeverSendTheirCodeForTranslation() async {
        let service = SummaryTranslationDouble(); let translation = SummaryTranslationCoordinator(translator: service)
        for marker in ["````", "~~~~"] {
            let original = "# Decisions\n\n\(marker)swift\n\(marker.prefix(3))\nprivate_code()\n"
                + "\(marker) invalid closing text\nstill_code()\n\(marker)\nShip Friday."
            translation.update(source: original, conversationID: marker, target: "fr")
            translation.request(); await settle()
            XCTAssertEqual(service.calls, ["Decisions", "Ship Friday."])
            XCTAssertEqual(translation.translatedText, original.replacingOccurrences(of: "Decisions", with: "Décisions")
                .replacingOccurrences(of: "Ship Friday.", with: "Livrer vendredi."))
            service.calls = []
        }
    }
    func testSummaryLimitsSameLanguageAndLongProseKeepOriginalSafe() async {
        let service = SummaryTranslationDouble(); let translation = SummaryTranslationCoordinator(translator: service)
        for (source, target, generating) in [("", "fr", false), ("Draft", "fr", true),
                                             ("Saved", "bad", false), (String(repeating: "x", count: 100_001), "fr", false)] {
            translation.update(source: source, conversationID: UUID().uuidString, target: target, isGenerating: generating)
            translation.request(); await settle()
            XCTAssertFalse(translation.canTranslate); XCTAssertNotNil(translation.problem)
            XCTAssertNil(translation.translatedText); XCTAssertEqual(service.calls, [])
            XCTAssertEqual(translation.source, source)
        }
        let original = "  1. Ship Friday.  \n\n~~~\nkeep(this_code)\n~~~"
        translation.update(source: original, conversationID: "same", target: "en")
        translation.request(); await settle()
        XCTAssertEqual(translation.translatedText, original)
        XCTAssertEqual(service.calls, [], "Same-language summary needs no model")
        let prose = String(repeating: "A long sentence. ", count: 700)
        translation.update(source: prose, conversationID: "long", target: "fr")
        translation.request(); await settle()
        XCTAssertNotNil(translation.translatedText)
        XCTAssertTrue(service.calls.allSatisfy { $0.count <= 8_000 })
        XCTAssertGreaterThan(service.calls.count, 1)
        XCTAssertTrue(translation.matches(source: prose, conversationID: "long", target: "fr"))
        XCTAssertFalse(translation.matches(source: prose, conversationID: "other", target: "fr"))
        translation.reset(); XCTAssertNil(translation.translatedText)
    }
    func testMissingSummaryPacksShowSetupAndNeverSendContentUntilExplicitRetry() async {
        let service = SummaryTranslationDouble(); service.ready = false
        let translation = SummaryTranslationCoordinator(translator: service)
        translation.update(source: "Ship Friday.", conversationID: "a", target: "fr")
        translation.request(); await settle()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(translation.worker.availability.setupAction, "Prepare languages")
        XCTAssertNil(translation.translatedText)
        service.ready = true; translation.worker.retry(); await settle()
        XCTAssertEqual(translation.translatedText, "Livrer vendredi.")
    }
}

@MainActor private final class SummaryTranslationDouble: TranscriptTranslating {
    var calls: [String] = []
    var holdNext = false
    var ready = true
    private var held: CheckedContinuation<Void, Never>?
    func sourceLanguage(for text: String, hint: String?) -> String? { "en" }
    func availability(source: String, target: String) async -> FeatureAvailability {
        ready ? .ready : .setupRequired(reason: "Download French", action: "Prepare languages")
    }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        calls.append(text)
        if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
        if target == "es" { return "Entregar el viernes." }
        return text == "Decisions" ? "Décisions" : "Livrer vendredi."
    }
    func release() { held?.resume(); held = nil }
    func cancel() {}
}
