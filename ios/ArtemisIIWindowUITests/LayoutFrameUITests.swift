import XCTest

/// Portrait and landscape playback. The map caption and the Spatial row stay
/// on screen and clear of each other. The landscape rail scrolls instead of
/// running past the bottom.
@MainActor
final class LayoutFrameUITests: XCTestCase {
    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
        super.tearDown()
    }

    func testFramesStayInsideTheScreenInBothOrientations() {
        let app = XCUIApplication()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let map = element(named: "geographic-targets", in: app)
        let spatial = element(named: "spatial-toggle", in: app)
        XCTAssertTrue(spatial.waitForExistence(timeout: 15))
        XCTAssertTrue(map.waitForExistence(timeout: 15))

        let column = scroller("phone-column", in: app)
        reveal(map, using: column)
        assertInside(map, screen: app.frame)
        assertInside(spatial, screen: app.frame)
        XCTAssertFalse(map.frame.intersects(spatial.frame))
        let note = element(named: "spatial-note", in: app)
        if note.exists {
            assertInside(note, screen: app.frame)
            XCTAssertFalse(map.frame.intersects(note.frame))
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        // XCUIApplication.frame stays portrait after rotation. The window
        // bounds are the landscape screen.
        let rail = app.scrollViews["landscape-rail"]
        XCTAssertTrue(rail.waitForExistence(timeout: 8))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let screen = window.frame
        assertInside(rail, screen: screen)
        assertInside(spatial, screen: screen)
        reveal(map, using: rail)
        assertInside(map, screen: screen)
        assertInside(map, screen: rail.frame.insetBy(dx: -1, dy: -1))
        if spatial.exists && spatial.frame.intersects(screen) {
            XCTAssertFalse(map.frame.intersects(spatial.frame))
        }
    }

    private func element(named identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scroller(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let typed = app.scrollViews[identifier]
        if typed.waitForExistence(timeout: 5) {
            return typed
        }
        let any = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(any.waitForExistence(timeout: 5))
        return any
    }

    private func reveal(_ element: XCUIElement, using scroller: XCUIElement) {
        for _ in 0..<12 {
            if contains(element.frame, in: scroller.frame.insetBy(dx: -1, dy: -1)) {
                return
            }
            let frame = element.frame
            let bounds = scroller.frame
            let start: CGVector
            let end: CGVector
            if frame.maxY > bounds.maxY + 1 {
                start = CGVector(dx: 0.5, dy: 0.75)
                end = CGVector(dx: 0.5, dy: 0.35)
            } else if frame.minY < bounds.minY - 1 {
                start = CGVector(dx: 0.5, dy: 0.35)
                end = CGVector(dx: 0.5, dy: 0.75)
            } else {
                return
            }
            scroller.coordinate(withNormalizedOffset: start)
                .press(forDuration: 0.05, thenDragTo: scroller.coordinate(withNormalizedOffset: end))
        }
    }

    private func assertInside(
        _ element: XCUIElement,
        screen: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1, "\(frame) outside \(screen)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 1, "\(frame) outside \(screen)", file: file, line: line)
    }

    private func contains(_ frame: CGRect, in screen: CGRect) -> Bool {
        frame.minX >= screen.minX - 1
            && frame.minY >= screen.minY - 1
            && frame.maxX <= screen.maxX + 1
            && frame.maxY <= screen.maxY + 1
            && frame.width > 1
            && frame.height > 1
    }
}
