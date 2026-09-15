import XCTest
@testable import ListenToMeCore

/// Issue #136 (1): the rail's Engine line must describe the engine the live run is using, not the
/// saved setting — a change mid-recording only takes effect at the next Start.
final class TranscriptionEngineLabelTests: XCTestCase {

    func testNamesEveryStoredEngineIDAndDefaultsUnknownToSpeechAnalyzer() {
        XCTAssertEqual(TranscriptionEngineLabel.name("speechRecognizer"), "SpeechRecognizer")
        XCTAssertEqual(TranscriptionEngineLabel.name("whisperKit"), "WhisperKit")
        XCTAssertEqual(TranscriptionEngineLabel.name("speechAnalyzer"), "SpeechAnalyzer")
        XCTAssertEqual(TranscriptionEngineLabel.name(""), "SpeechAnalyzer")
    }

    func testIdleRailShowsTheSavedSetting() {
        XCTAssertEqual(TranscriptionEngineLabel.rail(active: nil, saved: "whisperKit"), "WhisperKit")
        XCTAssertEqual(TranscriptionEngineLabel.rail(active: nil, saved: "speechAnalyzer"), "SpeechAnalyzer")
    }

    func testRunningRailShowsTheRunningEngineWithNoSuffixWhenTheSettingAgrees() {
        XCTAssertEqual(TranscriptionEngineLabel.rail(active: "whisperKit", saved: "whisperKit"),
                       "WhisperKit")
    }

    func testChangingTheEngineMidRunKeepsTheRunningEngineAndFlagsThePendingOne() {
        XCTAssertEqual(TranscriptionEngineLabel.rail(active: "speechAnalyzer", saved: "whisperKit"),
                       "SpeechAnalyzer · WhisperKit next start")
        XCTAssertEqual(TranscriptionEngineLabel.rail(active: "whisperKit", saved: "speechRecognizer"),
                       "WhisperKit · SpeechRecognizer next start")
    }

    func testIDsThatRenderToTheSameNameAreNotReportedAsPending() {
        // Both resolve to SpeechAnalyzer, so there is nothing for the user to act on.
        XCTAssertEqual(TranscriptionEngineLabel.rail(active: "", saved: "speechAnalyzer"),
                       "SpeechAnalyzer")
    }
}
