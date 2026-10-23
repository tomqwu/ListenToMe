import XCTest

extension XCTestCase {
    /// Scrolls a settings form until `element` sits fully inside the visible area above the keyboard.
    @MainActor
    func revealSettingsControl(_ element: XCUIElement, in container: XCUIElement, towardTop: Bool = false) {
        XCTAssertTrue(container.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            let app = XCUIApplication()
            var bounds = container.frame.intersection(app.windows.firstMatch.frame)
            if app.keyboards.firstMatch.exists {
                bounds.size.height = max(0, min(bounds.maxY, app.keyboards.firstMatch.frame.minY) - bounds.minY)
            }
            if element.exists, element.isHittable,
               element.frame.minY > bounds.minY + 90, element.frame.maxY < bounds.maxY - 5 { return }
            let moveDown = element.exists ? element.frame.minY <= bounds.minY + 90 : towardTop
            let origin = container.coordinate(withNormalizedOffset: .zero)
            let xOffset = bounds.midX - container.frame.minX
            let yOffset = bounds.minY - container.frame.minY
            let start = origin.withOffset(CGVector(dx: xOffset, dy: yOffset + bounds.height * (moveDown ? 0.4 : 0.65)))
            let end = origin.withOffset(CGVector(dx: xOffset, dy: yOffset + bounds.height * (moveDown ? 0.65 : 0.4)))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
}
