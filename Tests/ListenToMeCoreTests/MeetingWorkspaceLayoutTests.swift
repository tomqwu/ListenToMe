import XCTest
@testable import ListenToMeCore

final class MeetingWorkspaceLayoutTests: XCTestCase {
    func testPhonePortraitAndLandscapeUseTheAvailableWorkspace() {
        XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: 362, height: 550, accessibilityText: false), .vertical)
        XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: 750, height: 180, accessibilityText: false), .twoPane)
        XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: 639, height: 200, accessibilityText: false), .scrolling)
        XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: 640, height: 180, accessibilityText: false), .twoPane)
        XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: 750, height: 179, accessibilityText: false), .scrolling)
    }

    func testWideWindowsAndAccessibilityKeepTheirExistingReadingLayouts() {
        XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: 900, height: 700, accessibilityText: false), .wide)
        for (width, height) in [(900.0, 700.0), (750, 180), (362, 550)] {
            XCTAssertEqual(MeetingWorkspaceLayout.resolve(width: width, height: height, accessibilityText: true), .scrolling)
        }
    }
}
