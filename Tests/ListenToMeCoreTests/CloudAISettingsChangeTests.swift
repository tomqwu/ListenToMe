import XCTest
@testable import ListenToMeCore

/// macOS saves the cloud AI service and key all-or-nothing (issue #214): the plan validates before
/// any write, and a key is only ever stored for one vendor's own Keychain item and origin.
final class CloudAISettingsChangeTests: XCTestCase {
    func testThePlanValidatesBeforeAnythingIsWritten() throws {
        XCTAssertThrowsError(try CloudAISettingsChange.plan(usesCloudAI: true, vendor: nil, key: "", keyEdited: false)) {
            XCTAssertEqual($0 as? CloudAISettingsChange.ValidationError, .noService)
        }
        XCTAssertThrowsError(try CloudAISettingsChange.plan(usesCloudAI: false, vendor: nil, key: "k", keyEdited: true)) {
            XCTAssertEqual($0 as? CloudAISettingsChange.ValidationError, .keyWithoutService)
        }
        XCTAssertEqual(try CloudAISettingsChange.plan(usesCloudAI: false, vendor: nil, key: "", keyEdited: false),
                       CloudAISettingsChange(vendor: nil, keyAction: .keep))
        XCTAssertEqual(try CloudAISettingsChange.plan(usesCloudAI: true, vendor: .groq, key: "k", keyEdited: false).keyAction,
                       .keep)
        XCTAssertEqual(try CloudAISettingsChange.plan(usesCloudAI: true, vendor: .anthropic, key: " sk-ant ", keyEdited: true),
                       CloudAISettingsChange(vendor: .anthropic, keyAction: .store(
                        key: "sk-ant", account: "cloud-ai-anthropic", origin: "https://api.anthropic.com:443")))
        XCTAssertEqual(try CloudAISettingsChange.plan(usesCloudAI: false, vendor: .xAI, key: "", keyEdited: true).keyAction,
                       .remove(account: "cloud-ai-xai"))
        for error in [CloudAISettingsChange.ValidationError.noService, .keyWithoutService] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
