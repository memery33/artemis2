import XCTest

/// The frosted sheet opens from a swipe on the bottom edge, not only from a tap.
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

    func testSwipeUpOnTheBottomEdgeOpensThePanel() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let edge = app.descendants(matching: .any)["panel-edge"]
        XCTAssertTrue(edge.waitForExistence(timeout: 8))
        let start = edge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        start.press(forDuration: 0.05, thenDragTo: finish)

        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: toggle)
        wait(for: [playing], timeout: 5)
        XCTAssertEqual(toggle.label, "Pause")
    }
}
