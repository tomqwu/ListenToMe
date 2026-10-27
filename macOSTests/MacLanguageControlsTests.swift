import AppKit
import SwiftUI
import XCTest
import ListenToMeCore

/// Exercises the actual shared native controls and Core session binding without opening personal
/// history, requesting audio permissions, using cloud inference or requiring a desktop unlock.
@MainActor
final class MacLanguageControlsTests: XCTestCase {
    func testWindowTranslationSuspensionFencesBothWorkersAndResumesOnReturn() async {
        let live = MacTranslationControlDouble(); live.holdNext = true
        let summary = MacTranslationControlDouble(); summary.holdNext = true
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { fatalError("No capture") }, makeTranscriber: { fatalError("No capture") },
            makeProvider: { _ in fatalError("No AI") }, models: [:])
        session.liveTranslation.translator = live; session.summaryTranslation.worker.translator = summary
        let lines: [TranscriptSegment] = ["First phrase.", "Second phrase."].map {
            .init(source: .others, text: $0, isFinal: true, start: 0, end: 1, language: "en")
        }
        let record = SessionRecord(id: "closed", title: "Saved", date: Date(), transcript: "", summary: "Summary.\nNext.",
            segments: lines, languageOptions: .init(translateTranscript: true, translationTarget: "fr",
                                                     summaryTranslationTarget: "fr"))
        XCTAssertTrue(session.restoreConversation(record)); session.summaryTranslation.request()
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(live.targets.count, 1); XCTAssertEqual(summary.targets.count, 1)
        session.setTranslationSuspended(true); live.release(); summary.release()
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(live.targets.count, 1); XCTAssertEqual(summary.targets.count, 1)
        XCTAssertNil(session.liveTranslation.text(for: lines[0])); XCTAssertNil(session.summaryTranslation.translatedText)
        session.setTranslationSuspended(false)
        for _ in 0..<300 { await Task.yield() }
        XCTAssertEqual(session.liveTranslation.text(for: lines[1]), "La réunion commence demain.")
        XCTAssertNotNil(session.summaryTranslation.translatedText)
        XCTAssertEqual(session.store.utterances, lines)
    }
    func testNativeControlsBindingTranslatesOriginalAndRendersNarrowOptions() async throws {
        let service = MacTranslationControlDouble()
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(),
            makeCapture: { fatalError("This text-only contract must not start capture") },
            makeTranscriber: { fatalError("This text-only contract must not start recognition") },
            makeProvider: { _ in fatalError("Translation must not use an AI provider") }, models: [:])
        session.liveTranslation.translator = service
        let original = TranscriptSegment(source: .others, text: "The meeting starts tomorrow.",
                                         isFinal: true, start: 0, end: 2, language: "en")
        session.store.apply(original)
        session.languageOptions = .init(translationTarget: "fr", summaryTranslationTarget: "ja")
        let controls = ConversationLanguageControls(options: Binding(get: { session.languageOptions },
            set: { session.languageOptions = $0 }), translation: session.liveTranslation, conversationID: "native-contract")
        let renderer = ImageRenderer(content: controls.padding(12).frame(width: 220, alignment: .topLeading)
            .background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        let snapshot = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        image.name = "Mac narrow language controls SwiftUI render"; image.lifetime = .keepAlways; add(image)
        // SwiftUI's unhosted AX tree is unavailable in the locked test runner. Exercise the
        // control's real Binding and retain a SwiftUI render; the iOS UI suite presses the same
        // shared SwiftUI switch. This is not an installed Mac GUI acceptance claim.
        controls.options.translateTranscript = true
        for _ in 0..<200 { await Task.yield() }
        XCTAssertTrue(session.languageOptions.translateTranscript)
        XCTAssertEqual(session.languageOptions.summaryTranslationTarget, "ja")
        XCTAssertEqual(session.liveTranslation.text(for: original), "La réunion commence demain.")
        XCTAssertEqual(session.store.utterances, [original])
        XCTAssertEqual(service.targets, ["fr"])

    }

}

@MainActor private final class MacTranslationControlDouble: TranscriptTranslating {
    var targets: [String] = []
    var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    func release() { held?.resume(); held = nil }
    func sourceLanguage(for text: String, hint: String?) -> String? { hint ?? "en" }
    func availability(source: String, target: String) async -> FeatureAvailability { .ready }
    func translate(_ text: String, source: String, target: String) async throws -> String {
        targets.append(target)
        if holdNext { holdNext = false; await withCheckedContinuation { held = $0 } }
        return "La réunion commence demain."
    }
    func cancel() {}
}
