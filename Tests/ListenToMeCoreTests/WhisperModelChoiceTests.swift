import XCTest
@testable import ListenToMeCore

final class WhisperModelChoiceTests: XCTestCase {
    func testSelectionPersistsAndInvalidPreferencesKeepBase() throws {
        let name = "WhisperChoiceTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(WhisperModelChoice.load(from: defaults), .base)
        for choice in WhisperModelChoice.allCases {
            choice.save(to: defaults)
            XCTAssertEqual(WhisperModelChoice.load(from: defaults), choice)
        }
        defaults.set("large-v3", forKey: "whisperModelSize")
        XCTAssertEqual(WhisperModelChoice.load(from: defaults), .base)
        defaults.set(123, forKey: "whisperModelSize")
        XCTAssertEqual(WhisperModelChoice.load(from: defaults), .base)
    }

    func testOnlyRequestedMultilingualVariantIsAccepted() {
        for choice in WhisperModelChoice.allCases {
            XCTAssertTrue(choice.matchesLoadedVariant(choice.rawValue))
            XCTAssertFalse(choice.matchesLoadedVariant(choice.rawValue + ".en"))
            for other in WhisperModelChoice.allCases where other != choice {
                XCTAssertFalse(choice.matchesLoadedVariant(other.rawValue))
            }
            XCTAssertEqual(choice.id, choice.rawValue)
            XCTAssertFalse(choice.title.isEmpty)
            XCTAssertFalse(choice.tradeoff.isEmpty)
        }
    }
}
