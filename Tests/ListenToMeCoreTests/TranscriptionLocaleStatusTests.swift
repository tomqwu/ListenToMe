import XCTest
@testable import ListenToMeCore

/// Issue #136 (4): an unsupported transcription language silently became en-US, with the resolved
/// identifier as the only (easily missed) evidence.
final class TranscriptionLocaleStatusTests: XCTestCase {

    func testRunningStatusNamesTheResolvedLanguage() {
        XCTAssertEqual(TranscriptionLocaleStatus.running("zh-TW"),
                       "Transcription: on-device · zh-TW")
    }

    func testFallbackStatusNamesBothTheRequestedAndTheSubstitutedLanguage() {
        let status = TranscriptionLocaleStatus.fallback(requested: "pt-BR", resolved: "en-US")
        XCTAssertTrue(status.contains("pt-BR"), status)
        XCTAssertTrue(status.contains("en-US"), status)
        XCTAssertTrue(status.contains("isn't supported"), status)
    }

    func testEveryStatusKeepsTheTranscriptionPrefixTheSessionLooksFor() {
        // MeetingSession.stopAndWait() only replaces a status that starts with "Transcription:".
        XCTAssertTrue(TranscriptionLocaleStatus.running("en-US").hasPrefix("Transcription:"))
        XCTAssertTrue(TranscriptionLocaleStatus.fallback(requested: "hi-IN", resolved: "en-US")
            .hasPrefix("Transcription:"))
    }
}
