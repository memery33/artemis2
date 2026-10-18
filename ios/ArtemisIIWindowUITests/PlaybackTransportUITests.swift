import XCTest

/// The dock play control is the same pause and resume as the lock screen.
@MainActor
final class PlaybackTransportUITests: XCTestCase {
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

    func testPlayPauseStopsAndResumesTheClock() {
        let app = XCUIApplication()
        app.launch()
        let begin = app.buttons["Tap to begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        wait(for: [label("Pause", on: toggle)], timeout: 5)
        XCTAssertTrue(app.buttons["skip-back"].exists)
        XCTAssertTrue(app.buttons["skip-forward"].exists)

        let clock = app.descendants(matching: .any)["mission-clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 8))

        toggle.tap()
        wait(for: [label("Play", on: toggle)], timeout: 5)
        let frozen = clock.label
        XCTAssertFalse(frozen.isEmpty)

        let hold = expectation(description: "paused clock")
        hold.isInverted = true
        wait(for: [hold], timeout: 2)
        XCTAssertEqual(clock.label, frozen)

        toggle.tap()
        wait(for: [label("Pause", on: toggle)], timeout: 5)
        wait(for: [labelChanged(from: frozen, on: clock)], timeout: 5)
    }

    private func label(_ text: String, on element: XCUIElement) -> XCTNSPredicateExpectation {
        XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
    }

    private func labelChanged(from text: String, on element: XCUIElement) -> XCTNSPredicateExpectation {
        XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", text), object: element)
    }
}
