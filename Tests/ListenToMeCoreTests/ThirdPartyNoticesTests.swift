import XCTest
@testable import ListenToMeCore

/// Issue #202: both apps ship the license of every resolved SwiftPM package, and a dependency added
/// or bumped without regenerating `App/ThirdPartyNotices.txt` fails here (and in CI).
final class ThirdPartyNoticesTests: XCTestCase {
    private let rule = ThirdPartyNotices.separator

    private var sample: String {
        """
        ListenToMe third-party software notices

        These notices accompany the dependency versions in Config/Package.resolved.


        \(rule)
        whisperkit 0.18.0
        https://github.com/argmaxinc/WhisperKit
        Revision: aaa111


        --- LICENSE ---

        MIT License

        Copyright (c) 2024 argmax, inc.

        \(rule)
        swift-asn1 1.7.1
        https://github.com/apple/swift-asn1.git
        Revision: bbb222

        --- LICENSE.txt ---
        Apache License

        --- NOTICE.txt ---
        The SwiftASN1 Project
        """
    }

    func testParsesEachPackageSectionWithItsLicenseText() {
        let notices = ThirdPartyNotices.parse(sample)
        XCTAssertEqual(notices.map(\.identity), ["whisperkit", "swift-asn1"])
        XCTAssertEqual(notices[0].version, "0.18.0")
        XCTAssertEqual(notices[0].url, "https://github.com/argmaxinc/WhisperKit")
        XCTAssertEqual(notices[0].revision, "aaa111")
        XCTAssertEqual(notices[0].text, "--- LICENSE ---\n\nMIT License\n\nCopyright (c) 2024 argmax, inc.")
        XCTAssertTrue(notices[1].text.hasSuffix("--- NOTICE.txt ---\nThe SwiftASN1 Project"),
                      "Every license file of a package stays in its notice")
        XCTAssertEqual(notices[1].id, "swift-asn1")
    }

    func testDisplayNameIsTheRepositoryName() {
        let notices = ThirdPartyNotices.parse(sample)
        XCTAssertEqual(notices.map(\.displayName), ["WhisperKit", "swift-asn1"])
        let bare = ThirdPartyNotice(identity: "x", version: "1", url: "", revision: "r", text: "t")
        XCTAssertEqual(bare.displayName, "x", "No URL falls back to the identity")
        let dotGit = ThirdPartyNotice(identity: "y", version: "1", url: "https://h/.git", revision: "r", text: "t")
        XCTAssertEqual(dotGit.displayName, "y")
    }

    func testMalformedSectionsAndThePreambleAreSkipped() {
        let text = """
        Preamble only
        \(rule)
        no-version-here
        https://example.com/a
        Revision: r1

        License
        \(rule)
        pkg 1.0
        https://example.com/b
        Commit: r2

        License
        \(rule)
        empty 1.0
        https://example.com/c
        Revision: r3

        \(rule)
        short 1.0
        """
        XCTAssertEqual(ThirdPartyNotices.parse(text), [])
        XCTAssertEqual(ThirdPartyNotices.parse("No notices at all"), [])
        XCTAssertEqual(ThirdPartyNotices.parse("\(rule)\r\nok 2.0\r\nhttps://h/ok\r\nRevision: r\r\nText\r\n")
                        .map(\.text), ["Text"], "Windows line endings parse the same")
    }

    func testMissingReportsAbsentAndOutdatedPackages() throws {
        let json = Data("""
        {"pins":[
          {"identity":"whisperkit","kind":"remoteSourceControl","location":"https://github.com/argmaxinc/WhisperKit",
           "state":{"revision":"aaa111","version":"0.18.0"}},
          {"identity":"swift-asn1","kind":"remoteSourceControl","location":"https://github.com/apple/swift-asn1.git",
           "state":{"revision":"ccc333","version":"1.8.0"}},
          {"identity":"newpkg","kind":"remoteSourceControl","location":"https://example.com/newpkg.git",
           "state":{"branch":"main","revision":"ddd444"}}
        ],"version":3}
        """.utf8)
        let pins = try ThirdPartyNotices.pins(fromResolved: json)
        XCTAssertEqual(pins.last, .init(identity: "newpkg", location: "https://example.com/newpkg.git",
                                        version: nil, revision: "ddd444"), "A branch pin has no version")
        let missing = ThirdPartyNotices.missing(pins, in: ThirdPartyNotices.parse(sample))
        XCTAssertEqual(missing.map(\.identity), ["swift-asn1", "newpkg"],
                       "A bumped revision needs a regenerated notice; a new package needs one at all")
        XCTAssertThrowsError(try ThirdPartyNotices.pins(fromResolved: Data("{}".utf8)))
    }

    /// The release guard: the shipped notices cover every package `Config/Package.resolved` pins.
    func testShippedNoticesCoverEveryResolvedPackage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resolved = try Data(contentsOf: root.appendingPathComponent("Config/Package.resolved"))
        let text = try String(contentsOf: root.appendingPathComponent("App/ThirdPartyNotices.txt"), encoding: .utf8)
        let pins = try ThirdPartyNotices.pins(fromResolved: resolved)
        let notices = ThirdPartyNotices.parse(text)
        XCTAssertFalse(pins.isEmpty)
        XCTAssertEqual(ThirdPartyNotices.missing(pins, in: notices).map(\.identity), [],
                       "Regenerate App/ThirdPartyNotices.txt for these packages (see docs/RELEASING.md)")
        for notice in notices {
            XCTAssertTrue(notice.text.contains("--- "), "\(notice.identity) has no license file")
            XCTAssertEqual(pins.first { $0.identity == notice.identity }?.version, notice.version)
        }
        XCTAssertTrue(notices.contains { $0.identity == "whisperkit" })
        XCTAssertTrue(notices.contains { $0.identity == "fluidaudio" })
    }
}
