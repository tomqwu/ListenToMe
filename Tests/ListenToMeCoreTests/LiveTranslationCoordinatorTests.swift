import XCTest
@testable import ListenToMeCore

@MainActor
final class LiveTranslationCoordinatorTests: XCTestCase {
    private func line(_ text: String, final: Bool = true) -> TranscriptSegment {
        .init(source: .others, text: text, isFinal: final, start: 1, end: 3, speakerID: "second", language: "en")
    }
    private func settle(_ coordinator: LiveTranslationCoordinator) async {
        for _ in 0..<200 { await Task.yield() }
    }
    func testOptInTranslatesFinalSpeechOnceAndPreservesOriginalAndSpeaker() async {
        let service = TranslationDouble(); let translation = LiveTranslationCoordinator(translator: service)
        let original = line("Good morning."); let partial = line("Good", final: false)
        let options = ConversationLanguageOptions(translateTranscript: true, translationTarget: "fr")
        translation.update(conversationID: "a", segments: [original, partial], fallbackLanguage: "en", options: .init())
        await settle(translation)
        XCTAssertEqual(service.calls, [], "Off by default means no content processing or setup")
        translation.update(conversationID: "a", segments: [original, partial], fallbackLanguage: "en", options: options)
        await settle(translation)
        XCTAssertEqual(translation.text(for: original), "Bonjour.")
        XCTAssertNil(translation.text(for: partial))
        XCTAssertEqual(service.calls, ["Good morning."])
        translation.update(conversationID: "a", segments: [original], fallbackLanguage: "en", options: options)
        await settle(translation)
        XCTAssertEqual(service.calls.count, 1)
        XCTAssertEqual(original.text, "Good morning."); XCTAssertEqual(original.speakerID, "second")
    }
    func testMissingAndUnsupportedPacksNeverTranslateOrDownload() async {
        for readiness in [FeatureAvailability.setupRequired(reason: "Download French", action: "Prepare languages"),
                          .unsupported(reason: "This pair is unavailable")] {
            let service = TranslationDouble(); service.readiness = readiness
            let translation = LiveTranslationCoordinator(translator: service); let original = line("Good morning.")
            translation.update(conversationID: "a", segments: [original], fallbackLanguage: "en",
                               options: .init(translateTranscript: true, translationTarget: "fr"))
            await settle(translation)
            XCTAssertEqual(translation.availability, readiness)
            XCTAssertEqual(service.calls, [])
            XCTAssertNotNil(translation.problems[original.id])
            XCTAssertNil(translation.text(for: original))
        }
    }
    func testInvalidUnknownEmptyAndFailedResultsKeepOriginalAndOfferRetry() async {
        let service = TranslationDouble()
        let translation = LiveTranslationCoordinator(translator: service)
        func update(_ original: TranscriptSegment, target: String = "fr") {
            translation.update(conversationID: UUID().uuidString, segments: [original], fallbackLanguage: nil,
                               options: .init(translateTranscript: true, translationTarget: target))
        }
        let huge = line(String(repeating: "x", count: 10_001))
        update(huge); await settle(translation)
        XCTAssertNotNil(translation.problems[huge.id]); XCTAssertTrue(service.calls.isEmpty)
        let original = line("Good morning.")
        update(original, target: "bad"); await settle(translation)
        XCTAssertNotNil(translation.problems[original.id]); XCTAssertTrue(service.calls.isEmpty)
        translation.translator = nil; update(original); await settle(translation)
        XCTAssertNotNil(translation.problems[original.id])
        translation.translator = service; service.unknown = true; update(original); await settle(translation)
        XCTAssertNotNil(translation.problems[original.id]); XCTAssertTrue(service.calls.isEmpty)
        service.unknown = false
        for value in ["", String(repeating: "x", count: 20_001)] {
            service.value = value; update(original); await settle(translation)
            XCTAssertNil(translation.text(for: original)); XCTAssertNotNil(translation.problems[original.id])
        }
        service.throwsError = true; update(original); await settle(translation)
        XCTAssertNil(translation.text(for: original)); XCTAssertNotNil(translation.problems[original.id])
        service.throwsError = false; service.value = nil; translation.retry(); await settle(translation)
        XCTAssertEqual(translation.text(for: original), "Bonjour.")
        XCTAssertTrue(translation.hasCompleted(original)); XCTAssertEqual(original.text, "Good morning.")
    }
    func testEditedBlockedLineRetriesAndSameLanguageNeedsNoTranslation() async {
        let service = TranslationDouble(); service.readiness = .temporarilyUnavailable(reason: "Try again")
        let translation = LiveTranslationCoordinator(translator: service); let original = line("Good morning.")
        let options = ConversationLanguageOptions(translateTranscript: true, translationTarget: "fr")
        translation.update(conversationID: "a", segments: [original], fallbackLanguage: "en", options: options)
        await settle(translation); XCTAssertNotNil(translation.problems[original.id])
        service.readiness = .ready
        let edited = TranscriptSegment(id: original.id, source: .others, text: "Good evening.",
                                       isFinal: true, start: 1, end: 3, language: "en")
        translation.update(conversationID: "a", segments: [edited], fallbackLanguage: "en", options: options)
        await settle(translation)
        XCTAssertEqual(translation.text(for: edited), "Bonjour.")
        XCTAssertNil(translation.problems[original.id])
        translation.update(conversationID: "a", segments: [edited], fallbackLanguage: "en",
                           options: .init(translateTranscript: true, translationTarget: "en"))
        await settle(translation)
        XCTAssertNil(translation.text(for: edited), "A same-language line must not show an empty translation label")
        XCTAssertEqual(service.calls, ["Good evening."])
    }

    func testAppendingLongConversationCoalescesOneWorkerAndResetDropsItsOutput() async {
        let service = TranslationDouble(); service.holdNext = true
        let translation = LiveTranslationCoordinator(translator: service)
        let options = ConversationLanguageOptions(translateTranscript: true, translationTarget: "fr")
        var lines = [line("Good morning.")]
        translation.update(conversationID: "a", segments: lines, fallbackLanguage: "en", options: options)
        await settle(translation)
        for _ in 0..<200 {
            lines.append(line("Another completed line."))
            translation.update(conversationID: "a", segments: lines, fallbackLanguage: "en", options: options)
        }
        XCTAssertEqual(service.calls.count, 1, "New speech must not restart or multiply native calls")
        XCTAssertEqual(translation.pendingCount, lines.count)
        translation.reset(); service.release(); await settle(translation)
        XCTAssertFalse(translation.isTranslating); XCTAssertEqual(translation.pendingCount, 0)
        XCTAssertNil(translation.text(for: lines[0])); XCTAssertEqual(service.maximumActive, 1)
    }


    func testSuspendedConversationStopsBacklogAndResumesOnlyOnForeground() async {
        let service = TranslationDouble(); service.holdNext = true
        let translation = LiveTranslationCoordinator(translator: service)
        let lines = [line("Good morning."), line("Another phrase.")]
        translation.update(conversationID: "a", segments: lines, fallbackLanguage: "en",
                           options: .init(translateTranscript: true, translationTarget: "fr"))
        await settle(translation); XCTAssertEqual(service.calls.count, 1)
        translation.setSuspended(true); service.release(); await settle(translation)
        XCTAssertEqual(service.calls.count, 1, "Backgrounding cannot keep draining old speech")
        XCTAssertNil(translation.text(for: lines[0]), "Held work cannot publish while suspended")
        translation.setSuspended(false); await settle(translation)
        XCTAssertEqual(translation.text(for: lines[0]), "Bonjour.")
        XCTAssertEqual(translation.text(for: lines[1]), "Bonjour.")
    }

    func testLateResultsCannotReturnAfterDisableTargetChangeEditDeleteOrNew() async {
        for change in ["disable", "target", "edit", "delete", "new"] {
            let service = TranslationDouble(); service.holdNext = true
            let translation = LiveTranslationCoordinator(translator: service)
            let original = line("Good morning.")
            var options = ConversationLanguageOptions(translateTranscript: true, translationTarget: "fr")
            translation.update(conversationID: "a", segments: [original], fallbackLanguage: "en", options: options)
            await settle(translation)
            XCTAssertEqual(service.calls.count, 1, change)
            var lines = [original]; var conversation = "a"
            switch change {
            case "disable": options.translateTranscript = false
            case "target": options.translationTarget = "es"
            case "edit": lines = [.init(id: original.id, source: .others, text: "Good evening.", isFinal: true,
                                         start: 1, end: 3, language: "en")]
            case "delete": lines = []
            default: conversation = "b"; lines = []
            }
            translation.update(conversationID: conversation, segments: lines, fallbackLanguage: "en", options: options)
            service.release(); await settle(translation)
            if change == "target" { XCTAssertEqual(translation.text(for: original), "Hola.") }
            else { XCTAssertNil(translation.text(for: original), change) }
            XCTAssertLessThanOrEqual(service.maximumActive, 1, "Language changes must not create concurrent native work")
        }
    }

}

@MainActor private final class TranslationDouble: TranscriptTranslating {
    var unknown = false
    var value: String?
    var throwsError = false
    var readiness = FeatureAvailability.ready
    var calls: [String] = []
    var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var active = 0
    var maximumActive = 0
    func release() { held?.resume(); held = nil }
    func sourceLanguage(for text: String, hint: String?) -> String? { unknown ? nil : (hint ?? "en") }
    func availability(source: String, target: String) async -> FeatureAvailability { readiness }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        calls.append(text); active += 1; maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
        if throwsError { throw NSError(domain: "test", code: 1) }
        return value ?? (target == "es" ? "Hola." : "Bonjour.")
    }
    func cancel() {}
}
