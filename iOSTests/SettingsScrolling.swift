import XCTest

extension XCTestCase {
    /// Scrolls a settings form until `element` sits fully inside the visible area above the keyboard.
    @MainActor
    func revealSettingsControl(_ element: XCUIElement, in container: XCUIElement, towardTop: Bool = false) {
        XCTAssertTrue(container.waitForExistence(timeout: 5))
        // The form can span six or more screens. Search with overlapping half-screen moves;
        // switch to smaller adjustments once the lazily created control exists.
        for _ in 0..<40 {
            let app = XCUIApplication()
            var bounds = container.frame.intersection(app.windows.firstMatch.frame)
            if app.keyboards.firstMatch.exists {
                bounds.size.height = max(0, min(bounds.maxY, app.keyboards.firstMatch.frame.minY) - bounds.minY)
            }
            if element.exists, element.isHittable,
               element.frame.minY > bounds.minY + 90, element.frame.maxY < bounds.maxY - 5 { return }
            let exists = element.exists
            let moveDown = exists ? element.frame.minY <= bounds.minY + 90 : towardTop
            let lower = exists ? 0.4 : 0.3
            let upper = exists ? 0.65 : 0.8
            let origin = container.coordinate(withNormalizedOffset: .zero)
            let xOffset = bounds.midX - container.frame.minX
            let yOffset = bounds.minY - container.frame.minY
            let start = origin.withOffset(CGVector(dx: xOffset, dy: yOffset + bounds.height * (moveDown ? lower : upper)))
            let end = origin.withOffset(CGVector(dx: xOffset, dy: yOffset + bounds.height * (moveDown ? upper : lower)))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "Settings control remained unreachable after bounded scrolling: \(element)")
    }
}
