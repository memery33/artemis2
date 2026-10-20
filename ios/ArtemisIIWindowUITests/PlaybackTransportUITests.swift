import XCTest

/// Play, pause, and the 15 second skips live in the frosted panel.
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
            FlybyUILaunch.endActivities()
        }
        super.tearDown()
    }

    func testPlayPauseStopsAndResumesTheClock() throws {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

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

        let paused = try XCTUnwrap(utcSeconds(frozen))
        app.buttons["skip-forward"].tap()
        wait(for: [labelChanged(from: frozen, on: clock)], timeout: 5)
        let forwarded = try XCTUnwrap(utcSeconds(clock.label))
        XCTAssertEqual(Double(forwarded - paused), 15, accuracy: 2)

        let forwardedLabel = clock.label
        app.buttons["skip-back"].tap()
        wait(for: [labelChanged(from: forwardedLabel, on: clock)], timeout: 5)
        let returned = try XCTUnwrap(utcSeconds(clock.label))
        XCTAssertEqual(Double(returned - forwarded), -15, accuracy: 2)

        let settled = clock.label
        toggle.tap()
        wait(for: [label("Pause", on: toggle)], timeout: 5)
        wait(for: [labelChanged(from: settled, on: clock)], timeout: 5)
    }

    private func utcSeconds(_ label: String) -> Int? {
        guard let match = label.range(of: #"\d{2}:\d{2}:\d{2}"#, options: .regularExpression) else { return nil }
        let clock = label[match]
        let parts = clock.split(separator: ":")
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]) else { return nil }
        return hour * 3600 + minute * 60 + second
    }

    private func label(_ text: String, on element: XCUIElement) -> XCTNSPredicateExpectation {
        XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)
    }

    private func labelChanged(from text: String, on element: XCUIElement) -> XCTNSPredicateExpectation {
        XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", text), object: element)
    }
}
