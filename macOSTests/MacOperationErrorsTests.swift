import XCTest
import ListenToMeCore

@MainActor
final class MacOperationErrorsTests: XCTestCase {
    func testImportFailureAndDismissalPreserveCaptureRecovery() {
        let errors = MacOperationErrors()
        errors.capture = CapturePreflight.deniedMessage
        errors.importFailed(CocoaError(.fileReadNoSuchFile))
        XCTAssertEqual(errors.capture, CapturePreflight.deniedMessage)
        XCTAssertTrue(errors.file?.contains("Couldn't import this recording") == true)
        errors.file = nil
        XCTAssertEqual(errors.capture, CapturePreflight.deniedMessage)
        errors.capture = nil
        XCTAssertNil(errors.capture)
    }
}
