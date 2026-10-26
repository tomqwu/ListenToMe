import XCTest

extension XCTestCase {
    /// Read an old heading through the actual unobscured viewport. A one-direction fling can
    /// overshoot a heading, and the safe-area Continue button must not receive the scroll gesture.
    @MainActor
    func revealReleaseHeading(_ heading: XCUIElement, in scroll: XCUIElement,
                              above continueButton: XCUIElement, app: XCUIApplication) {
        // Geometry is stable in this portrait journey; snapshot it once rather than spending
        // several accessibility round trips per page. The timeout is a hang safeguard, while
        // successful reachability and observed progress determine completion.
        var viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
        viewport.size.height = max(0, min(viewport.maxY, continueButton.frame.minY) - viewport.minY)
        let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter { $0.exists }
            .map { $0.frame.maxY }.filter { $0 > viewport.minY && $0 < viewport.midY }.max() ?? viewport.minY
        viewport = CGRect(x: viewport.minX, y: navigationBottom, width: viewport.width,
                          height: viewport.maxY - navigationBottom).insetBy(dx: 8, dy: 8)
        guard viewport.height > 80 else {
            XCTFail("Continue or navigation chrome leaves no readable release-history viewport")
            return
        }
        let containerFrame = scroll.frame
        let deadline = Date().addingTimeInterval(360)
        var previousDistance: CGFloat?
        var unchanged = 0
        while Date() < deadline {
            guard scroll.exists, continueButton.exists else {
                XCTFail("Release notes closed before the old heading was reached")
                return
            }
            let exists = heading.exists
            let frame = exists ? heading.frame : .zero
            if exists, viewport.contains(frame), heading.isHittable {
                XCTAssertTrue(continueButton.isHittable)
                return
            }
            let down = frame.height > 0 && frame.minY < viewport.minY
            let distance = down ? viewport.minY - frame.minY : frame.maxY - viewport.maxY
            if frame.height > 0 {
                if let previousDistance, distance >= previousDistance - 1 { unchanged += 1 } else { unchanged = 0 }
                previousDistance = distance
                if unchanged >= 4 { break }
            }
            print("Release history heading=\(frame), viewport=\(viewport), noProgress=\(unchanged)")
            let far = frame.height == 0 || distance > viewport.height * 2
            if far, !down, unchanged == 0 {
                // A native fling carries momentum. Press-and-drag alone advances only its
                // finger distance, which is too slow through many large-text release cards.
                scroll.swipeUp(velocity: .fast)
                continue
            }
            // Recover from overshoot or refine a nearby target using unobscured coordinates.
            let travel = far ? viewport.height * 0.9 : min(viewport.height * 0.45, max(40, distance + 16))
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            let xOffset = viewport.midX - containerFrame.minX
            let middle = viewport.midY - containerFrame.minY
            let start = origin.withOffset(CGVector(dx: xOffset, dy: middle + (down ? -travel : travel) / 2))
            let end = origin.withOffset(CGVector(dx: xOffset, dy: middle + (down ? travel : -travel) / 2))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: far ? .fast : .slow,
                        thenHoldForDuration: far ? 0 : 0.1)
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Release history stalled or timed out"
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Release history accessibility geometry"
        tree.lifetime = .keepAlways
        add(tree)
        XCTFail("Oldest release heading did not reach the unobscured viewport; inspect retained geometry and screenshot")
    }
}
