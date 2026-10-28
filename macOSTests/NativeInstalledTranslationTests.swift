import XCTest
import ListenToMeCore

/// Real installed Apple Translation acceptance. No injected translator, downloads or user content.
@MainActor
final class NativeInstalledTranslationTests: XCTestCase {
    func testActualInstalledChineseSummaryPreservesFactsCodeAndOriginalOrExplainsSetup() async throws {
        let original = """
        The budget is 120 dollars.

        The team will review the budget on Thursday.

        ```swift
        let budget = 120
        ```
        """
        let translation = SummaryTranslationCoordinator(translator: AppleTranscriptTranslator(),
                                                        requestTimeout: .seconds(45))
        defer { translation.cancel() }
        translation.update(source: original, conversationID: "native-installed-fixture", target: "zh-Hans")
        XCTAssertNil(translation.translatedText, "Opening Summary must not translate automatically")
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: .seconds(60))
        translation.request()
        while translation.worker.isTranslating || translation.worker.isDraining, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(translation.source, original, "The saved English summary remains authoritative")
        let elapsed = started.duration(to: clock.now)
        let branch: String
        switch translation.worker.availability {
        case .setupRequired(let reason, let action):
            branch = "setup-required"
            XCTAssertFalse(reason.isEmpty); XCTAssertEqual(action, "Prepare languages")
            XCTAssertNil(translation.translatedText)
        case .unsupported(let reason):
            branch = "unsupported"
            XCTAssertFalse(reason.isEmpty); XCTAssertNil(translation.translatedText)
        case .temporarilyUnavailable(let reason):
            branch = "native-failure"
            XCTFail("The actual native request must finish or explain pair setup: \(reason)")
        case .ready:
            branch = "installed-real-model"
            assertInstalledOutput(translation, original: original)
        }
        let note = "Actual Apple Translation branch: \(branch); target: zh-Hans; elapsed: \(elapsed); "
            + "isTranslating: \(translation.worker.isTranslating); isDraining: \(translation.worker.isDraining)\n"
            + "Derived synthetic output:\n\(translation.translatedText ?? "<none>")"
        let attachment = XCTAttachment(string: note)
        attachment.name = "Actual installed Chinese summary translation outcome"
        attachment.lifetime = .keepAlways; add(attachment)
        print("NativeInstalledTranslationTests branch=\(branch) elapsed=\(elapsed)")
        XCTAssertFalse(translation.worker.isTranslating, "A native request cannot leave an endless spinner")
        XCTAssertFalse(translation.worker.isDraining, "The native operation must exit within the acceptance budget")
    }
    private func assertInstalledOutput(_ translation: SummaryTranslationCoordinator, original: String) {
        guard let output = translation.translatedText else {
            XCTFail("An installed pair must produce a complete translation"); return
        }
        let lines = output.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, original.components(separatedBy: "\n").count)
        if lines.count >= 3 {
            for index in [0, 2] {
                XCTAssertFalse(lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertNotNil(lines[index].range(of: #"\p{Han}"#, options: .regularExpression),
                                "Both prose paragraphs must contain actual Chinese output")
            }
            let language = AppleTranscriptTranslator().sourceLanguage(for: lines[0] + "\n" + lines[2], hint: nil)
            XCTAssertTrue(language?.hasPrefix("zh") == true, "Native language detection recognizes Chinese output")
            XCTAssertTrue(lines[0].contains("120"), "Translation preserves the stated budget number")
            let weekdays = ["星期四", "周四", "礼拜四", "星期4", "周4", "Thursday"]
            XCTAssertTrue(weekdays.contains(where: lines[2].contains), "Translation preserves Thursday's meaning")
        }
        XCTAssertTrue(output.contains("```swift\nlet budget = 120\n```"), "Code is kept byte-for-byte")
        XCTAssertNotEqual(output, original)
    }

}
