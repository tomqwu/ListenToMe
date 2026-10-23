import ListenToMeCore
import XCTest
@testable import ListenToMeIOS

/// Issue #202: the app bundle carries the notices for the packages it links.
final class MobileAcknowledgementsTests: XCTestCase {
    func testTheAppBundlesANoticeForEachLinkedPackage() {
        let identities = Set(MobileAcknowledgements.bundledNotices().map(\.identity))
        for linked in ["whisperkit", "fluidaudio", "swift-transformers", "swift-jinja", "swift-collections",
                       "swift-crypto", "swift-asn1", "yyjson"] {
            XCTAssertTrue(identities.contains(linked), "\(linked) has no bundled license notice")
        }
    }

    func testAMissingNoticesFileShowsNothingRatherThanCrashing() {
        XCTAssertEqual(MobileAcknowledgements.bundledNotices(bundle: Bundle(for: Self.self)), [])
    }
}
