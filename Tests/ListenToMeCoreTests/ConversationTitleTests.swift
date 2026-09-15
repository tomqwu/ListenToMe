import XCTest
@testable import ListenToMeCore

/// Issue #136 (6): Load from Calendar may adopt the meeting's title, but only while the title is
/// still the auto-generated one — a title the user typed is never clobbered.
final class ConversationTitleTests: XCTestCase {

    func testGeneratedTitleCarriesThePrefixAndTheDate() {
        XCTAssertEqual(ConversationTitle.generated("Sep 13, 2:05 PM"),
                       "Conversation — Sep 13, 2:05 PM")
    }

    func testOnlyTheGeneratedTitleMayBeReplaced() {
        XCTAssertTrue(ConversationTitle.isGenerated(ConversationTitle.generated("Sep 13, 2:05 PM")))
        XCTAssertFalse(ConversationTitle.isGenerated("Q3 pricing review"))
        XCTAssertFalse(ConversationTitle.isGenerated(""))
        // An em dash elsewhere in a user's own title must not look generated.
        XCTAssertFalse(ConversationTitle.isGenerated("My conversation — notes"))
    }
}
