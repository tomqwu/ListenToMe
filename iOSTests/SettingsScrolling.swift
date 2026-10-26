import XCTest

extension XCTestCase {
    /// Scrolls a settings form until `element` sits fully inside the visible area above the keyboard.
    @MainActor
    func revealSettingsControl(_ element: XCUIElement, in container: XCUIElement, towardTop: Bool = false) {
        guard container.waitForExistence(timeout: 5) else {
            XCTFail("Settings form is not open")
            return
        }
        // The form can span six or more screens. Search with overlapping half-screen moves;
        // switch to smaller adjustments once the lazily created control exists.
        for _ in 0..<40 {
            let app = XCUIApplication()
            guard container.exists else {
                XCTFail("Settings closed while revealing a control")
                return
            }
            var bounds = container.frame.intersection(app.windows.firstMatch.frame)
            if app.keyboards.firstMatch.exists {
                bounds.size.height = max(0, min(bounds.maxY, app.keyboards.firstMatch.frame.minY) - bounds.minY)
            }
            // A fixed 90-point inset rejected the fully visible first row and pulled the sheet
            // down until it dismissed. Use the actual visible navigation bar as the occlusion.
            let navigationBottom = app.navigationBars.allElementsBoundByIndex
                .filter { $0.exists && $0.isHittable }
                .map { $0.frame.maxY }
                .filter { $0 > bounds.minY && $0 < bounds.midY }
                .max() ?? bounds.minY
            let visibleTop = max(bounds.minY, navigationBottom) + 5
            if element.exists, element.isHittable,
               element.frame.minY >= visibleTop, element.frame.maxY <= bounds.maxY - 5 { return }
            let exists = element.exists
            let moveDown = exists ? element.frame.minY < visibleTop : towardTop
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
