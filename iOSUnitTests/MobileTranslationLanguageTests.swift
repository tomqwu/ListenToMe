import XCTest
import ListenToMeCore
@testable import ListenToMeIOS

@MainActor
final class MobileTranslationLanguageTests: XCTestCase {
    func testSummaryTranslationIsSeparateFromGenerationAndSavedChoicesReopen() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, recordingSupport: { _ in .ready })
        let automatic = session.autoQuick
        defer { session.autoQuick = automatic }
        session.autoQuick = false
        let translator = MobileHeldTranslation(); translator.releaseFirst = true
        session.summaryTranslation.worker.translator = translator
        session.summary = "Original summary."
        session.languageOptions = .init(translationTarget: "es", summaryTranslationTarget: "fr")
        XCTAssertEqual(session.summaryTranslation.source, "Original summary.")
        XCTAssertFalse(session.summaryTranslation.isRequested)
        session.summaryTranslation.request()
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(session.summaryTranslation.translatedText, "Bonjour.")
        XCTAssertEqual(session.summary, "Original summary.")
        XCTAssertNil(session.generatingMode)
        XCTAssertTrue(session.save(announce: false))
        let reopened = MobileSession(storageDirectory: root, recordingSupport: { _ in .ready })
        XCTAssertEqual(reopened.languageOptions, session.languageOptions)
        XCTAssertEqual(reopened.summary, "Original summary.")
        XCTAssertFalse(reopened.summaryTranslation.isRequested, "A derived translation is never archived as the original")
        session.newConversation()
        XCTAssertNil(session.summaryTranslation.translatedText)
        XCTAssertTrue(session.summary.isEmpty)
    }
    func testBackgroundSuspendsPhoneTranslationAndForegroundResumesCurrentConversation() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, recordingSupport: { _ in .ready })
        let enabled = session.speakers.enabled; let automatic = session.autoQuick
        defer { session.speakers.enabled = enabled; session.autoQuick = automatic }
        session.speakers.enabled = false; session.autoQuick = false; session.applicationIsActive = { true }
        let translator = MobileHeldTranslation(); session.liveTranslation.translator = translator
        session.segments = [.init(source: .you, text: "Good morning.", isFinal: true, start: 0, end: 1, language: "en"),
                            .init(source: .you, text: "Next phrase.", isFinal: true, start: 1, end: 2, language: "en")]
        session.languageOptions = .init(translateTranscript: true, translationTarget: "fr")
        for _ in 0..<200 where translator.calls == 0 { await Task.yield() }
        XCTAssertEqual(translator.calls, 1)
        await session.handleScenePhase(.background)
        translator.release()
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(translator.calls, 1)
        XCTAssertNil(session.liveTranslation.text(for: session.segments[0]))
        XCTAssertTrue(session.languageOptions.translateTranscript, "Background does not erase the user's choice")
        await session.handleScenePhase(.active)
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(session.liveTranslation.text(for: session.segments[0]), "Bonjour.")
        XCTAssertEqual(session.liveTranslation.text(for: session.segments[1]), "Bonjour.")
    }

}

@MainActor private final class MobileHeldTranslation: TranscriptTranslating {
    var calls = 0
    var releaseFirst = false
    private var held: CheckedContinuation<Void, Never>?
    func sourceLanguage(for text: String, hint: String?) -> String? { "en" }
    func availability(source: String, target: String) async -> FeatureAvailability { .ready }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        calls += 1
        if calls == 1 && !releaseFirst { await withCheckedContinuation { held = $0 } }
        return "Bonjour."
    }
    func release() { held?.resume(); held = nil }
    func cancel() {}
}
