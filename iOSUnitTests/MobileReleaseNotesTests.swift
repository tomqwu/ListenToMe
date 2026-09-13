import XCTest
@testable import ListenToMeIOS

final class MobileReleaseNotesTests: XCTestCase {
    func testAcknowledgementIsPerInstalledBuildAndPersistsAcrossLaunches() throws {
        let name = "ReleaseNotesTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(MobileReleaseNotes.shouldPresent(defaults: defaults, identity: "1.10.1 (23)"))
        MobileReleaseNotes.acknowledge(defaults: defaults, identity: "1.10.1 (23)")
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertFalse(MobileReleaseNotes.shouldPresent(defaults: reopened, identity: "1.10.1 (23)"))
        XCTAssertTrue(MobileReleaseNotes.shouldPresent(defaults: reopened, identity: "1.10.1 (24)"))
        XCTAssertTrue(MobileReleaseNotes.shouldPresent(defaults: reopened, identity: "1.11.0 (25)"))
    }

    func testCurrentReleaseNotesMatchTheInstalledMarketingVersion() {
        XCTAssertEqual(MobileReleaseNotes.releases.first?.version, MobileReleaseNotes.version,
                       "A new app version needs matching bundled release notes")
        XCTAssertFalse(MobileReleaseNotes.build.isEmpty)
        XCTAssertFalse(MobileReleaseNotes.versionLabel.contains("—"))
    }
}
