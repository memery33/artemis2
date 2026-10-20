import XCTest

/// The panel opens while audio is playing, a crater opens from a milestone,
/// and the photograph never falls back to an empty black pane.
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
            FlybyUILaunch.endActivities()
        }
        super.tearDown()
    }

    func testPanelOpensWhileAudioPlaysAndACraterOpens() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let caption = element(named: "window-caption", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertLessThan(caption.frame.width, app.frame.width - 40)
        XCTAssertLessThan(caption.frame.height, app.frame.height * 0.5)
        assertNoBlackPane(in: app)

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()

        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: toggle)
        wait(for: [playing], timeout: 5)
        XCTAssertEqual(toggle.label, "Pause")

        let window = app.buttons["window-nikon"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        window.tap()
        XCTAssertEqual(toggle.label, "Pause")

        let crater = app.buttons["milestone-aristarchus"]
        XCTAssertTrue(crater.waitForExistence(timeout: 8))
        crater.tap()

        let page = element(named: "crater-page", in: app)
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        let why = element(named: "crater-why", in: app)
        XCTAssertTrue(why.waitForExistence(timeout: 8))
        XCTAssertTrue(why.label.contains("volcanic diversity"))
        XCTAssertTrue(element(named: "about-this-data", in: app).waitForExistence(timeout: 8))
        assertNoBlackPane(in: app)
    }

    private func assertNoBlackPane(in app: XCUIApplication) {
        let blocked = [
            "No Window 2 frame",
            "No Cab Cam frame",
            "Times are not shifted to fill the gap"
        ]
        for phrase in blocked {
            let match = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", phrase)
            ).firstMatch
            XCTAssertFalse(match.exists, phrase)
        }
    }

    private func element(named identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
