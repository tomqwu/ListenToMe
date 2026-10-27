import XCTest
import ListenToMeCore
#if os(iOS)
@testable import ListenToMeIOS
#endif

@MainActor
final class NativeAppleTranslationTests: XCTestCase {
    func testNativePairReadinessPreventsUnpreparedTranslationAndNeverSubstitutesLanguages() async {
        for status in [AppleTranscriptTranslator.PackStatus.downloadRequired, .unsupported] {
            var queries: [String] = []; var sent = false
            let adapter = AppleTranscriptTranslator(environment: .init(status: { source, target in
                queries.append(source + ":" + target); return status
            }, run: { _, _, _ in sent = true; return "Unexpected" }))
            let readiness = await adapter.availability(source: "en-US", target: "fr")
            XCTAssertFalse(readiness.canRun)
            XCTAssertNotNil(readiness.reason)
            if status == .downloadRequired { XCTAssertEqual(readiness.setupAction, "Prepare languages") }
            do { _ = try await adapter.translate("Good morning.", source: "en-US", target: "fr")
                XCTFail("An unprepared pair must never construct an installed-model request")
            } catch { /* The original transcript remains the user's source. */ }
            XCTAssertFalse(sent)
            XCTAssertEqual(queries, ["en-US:fr", "en-US:fr"])
        }
    }
    func testInstalledNativePairUsesExactOriginalTextAndExplicitTarget() async throws {
        var payload: [String] = []
        let adapter = AppleTranscriptTranslator(environment: .init(status: { _, _ in .installed },
            run: { text, source, target in payload = [text, source, target]; return "Bonjour." }))
        let readiness = await adapter.availability(source: "en", target: "fr")
        XCTAssertTrue(readiness.canRun)
        let output = try await adapter.translate("Good morning.", source: "en", target: "fr")
        XCTAssertEqual(output, "Bonjour."); XCTAssertEqual(payload, ["Good morning.", "en", "fr"])
        XCTAssertEqual(adapter.sourceLanguage(for: "An unrelated language.", hint: "zh-Hant"), "zh-Hant")
    }
}
