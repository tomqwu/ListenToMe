import XCTest
@testable import ListenToMeIOS

final class MobileReleaseNotesTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let name = "ReleaseNotesTests-" + UUID().uuidString
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testFirstInstallSeedsTheAcknowledgementInsteadOfPresentingAnUpdate() throws {
        let (store, name) = try makeDefaults()
        defer { store.removePersistentDomain(forName: name) }
        XCTAssertFalse(MobileReleaseNotes.shouldPresent(defaults: store, identity: "notes-a"),
                       "A brand-new install has no update to announce")
        XCTAssertEqual(store.string(forKey: MobileReleaseNotes.seenKey), "notes-a",
                       "The first launch records the bundled notes so a later launch stays quiet")
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertFalse(MobileReleaseNotes.shouldPresent(defaults: reopened, identity: "notes-a"))
    }

    func testOnlyChangedReleaseNotesPresentAgainAndAcknowledgementPersists() throws {
        let (store, name) = try makeDefaults()
        defer { store.removePersistentDomain(forName: name) }
        // An install from an earlier version already stored an identity, so new notes still show.
        store.set("1.10.2 (24)", forKey: MobileReleaseNotes.seenKey)
        XCTAssertTrue(MobileReleaseNotes.shouldPresent(defaults: store, identity: "notes-a"))
        MobileReleaseNotes.acknowledge(defaults: store, identity: "notes-a")
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertFalse(MobileReleaseNotes.shouldPresent(defaults: reopened, identity: "notes-a"))
        XCTAssertTrue(MobileReleaseNotes.shouldPresent(defaults: reopened, identity: "notes-b"))
    }

    func testNotesIdentityTracksTheNewestBundledReleaseNotTheBuildNumber() {
        let base = MobileReleaseNotes.Release(version: "2.0.0", title: "Title", details: ["One", "Two"])
        let sameNotes = MobileReleaseNotes.Release(version: "2.0.0", title: "Title", details: ["One", "Two"])
        let editedDetail = MobileReleaseNotes.Release(version: "2.0.0", title: "Title", details: ["One", "Three"])
        let editedTitle = MobileReleaseNotes.Release(version: "2.0.0", title: "Other", details: ["One", "Two"])
        XCTAssertEqual(MobileReleaseNotes.identity(for: base), MobileReleaseNotes.identity(for: sameNotes),
                       "A build bump with identical notes must not re-present What's New")
        XCTAssertNotEqual(MobileReleaseNotes.identity(for: base), MobileReleaseNotes.identity(for: editedDetail))
        XCTAssertNotEqual(MobileReleaseNotes.identity(for: base), MobileReleaseNotes.identity(for: editedTitle))
        XCTAssertFalse(MobileReleaseNotes.notesIdentity.contains(" (\(MobileReleaseNotes.build))"),
                       "The gate is keyed on the notes, not the installed build")
        XCTAssertTrue(MobileReleaseNotes.notesIdentity.hasPrefix(MobileReleaseNotes.releases[0].version))
    }

    func testNewestBundledReleaseIsLabelledAsThisUpdate() {
        XCTAssertEqual(MobileReleaseNotes.badge(for: MobileReleaseNotes.releases[0]), "IN THIS UPDATE")
        XCTAssertEqual(MobileReleaseNotes.badge(for: MobileReleaseNotes.releases[1]),
                       "VERSION \(MobileReleaseNotes.releases[1].version)")
    }

    func testCurrentReleaseNotesMatchTheInstalledMarketingVersion() {
        XCTAssertEqual(MobileReleaseNotes.releases.first?.version, MobileReleaseNotes.version,
                       "A new app version needs matching bundled release notes")
        XCTAssertFalse(MobileReleaseNotes.build.isEmpty)
        XCTAssertFalse(MobileReleaseNotes.versionLabel.contains("—"))
    }
}
