import XCTest

/// The frosted sheet opens from a swipe on the handle or the bottom edge, and a swipe down closes it.
@MainActor
final class PanelSwipeUITests: XCTestCase {
    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            XCUIDevice.shared.orientation = .portrait
            FlybyUILaunch.endActivities()
        }
        super.tearDown()
    }

    func testHandleAndEdgeSwipesOpenAndASwipeDownCloses() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let panel = app.descendants(matching: .any)["control-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.value as? String, "closed")

        let handle = app.buttons["open-panel"]
        XCTAssertTrue(handle.waitForExistence(timeout: 8))
        drag(handle, from: CGVector(dx: 0.5, dy: 0.4), to: app, at: CGVector(dx: 0.5, dy: 0.35))
        assertPanel("open", panel)

        let close = app.descendants(matching: .any)["close-panel"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        drag(close, from: CGVector(dx: 0.5, dy: 0.5), to: app, at: CGVector(dx: 0.5, dy: 0.78))
        assertPanel("closed", panel)

        let edge = app.descendants(matching: .any)["panel-edge"]
        XCTAssertTrue(edge.waitForExistence(timeout: 8))
        drag(edge, from: CGVector(dx: 0.4, dy: 0.5), to: app, at: CGVector(dx: 0.4, dy: 0.32))
        assertPanel("open", panel)
    }

    private func drag(_ element: XCUIElement, from start: CGVector, to root: XCUIApplication, at end: CGVector) {
        let origin = element.coordinate(withNormalizedOffset: start)
        let finish = root.coordinate(withNormalizedOffset: end)
        origin.press(forDuration: 0.05, thenDragTo: finish)
    }

    private func assertPanel(_ state: String, _ panel: XCUIElement) {
        let matched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", state),
            object: panel
        )
        wait(for: [matched], timeout: 5)
        XCTAssertEqual(panel.value as? String, state)
    }
}
