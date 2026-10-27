import AppKit
import XCTest

@MainActor
final class MacSpeakerRenameTests: XCTestCase {
    func testDoubleClickRenamesButSingleClickAndDisabledLabelDoNot() throws {
        let button = MacSpeakerNameButton(frame: .zero)
        var requests = 0
        button.rename = { requests += 1 }
        func event(_ count: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1))
        }
        button.mouseDown(with: try event(1))
        XCTAssertEqual(requests, 0)
        button.mouseDown(with: try event(2))
        XCTAssertEqual(requests, 1)
        button.isEnabled = false
        button.mouseDown(with: try event(2))
        XCTAssertEqual(requests, 1)
    }
    func testAccessibilityRenameAndNameValidation() {
        let button = MacSpeakerNameButton(frame: .zero)
        var requests = 0
        button.rename = { requests += 1 }
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(requests, 1)
        button.isEnabled = false
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertEqual(requests, 1)
        XCTAssertNil(SpeakerRenameEditor.normalized("  \n "))
        XCTAssertNil(SpeakerRenameEditor.normalized("Microphone"))
        XCTAssertNil(SpeakerRenameEditor.normalized("Apple Watch"))
        XCTAssertEqual(SpeakerRenameEditor.normalized("  Dana \n Lee  "), "Dana Lee")
        XCTAssertEqual(SpeakerRenameEditor.normalized(String(repeating: "a", count: 90))?.count, 80)
    }
}
