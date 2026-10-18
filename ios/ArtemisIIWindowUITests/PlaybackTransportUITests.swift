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

    func testPlayPauseStopsAndResumesTheClock() throws {
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

    /// VoiceOver increment uses the adjustable action, not a scrub that sticks.
    func testAccessibilityIncrementSkipsAboutFifteenSecondsWithoutFreezing() throws {
        let app = XCUIApplication()
        app.launch()
        let begin = app.buttons["Tap to begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        wait(for: [label("Pause", on: toggle)], timeout: 5)

        let clock = app.descendants(matching: .any)["mission-clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 8))
        toggle.tap()
        wait(for: [label("Play", on: toggle)], timeout: 5)
        let frozen = clock.label
        let hold = expectation(description: "paused before increment")
        hold.isInverted = true
        wait(for: [hold], timeout: 1)
        XCTAssertEqual(clock.label, frozen)

        let slider = app.sliders["mission-scrubber"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        _ = slider.perform(NSSelectorFromString("accessibilityIncrement"))

        wait(for: [labelChanged(from: frozen, on: clock)], timeout: 5)
        let paused = try XCTUnwrap(utcSeconds(frozen))
        let jumped = try XCTUnwrap(utcSeconds(clock.label))
        XCTAssertEqual(Double(jumped - paused), 15, accuracy: 2)
        let afterSkip = clock.label
        let stillPaused = expectation(description: "increment did not start a scrub freeze")
        stillPaused.isInverted = true
        wait(for: [stillPaused], timeout: 1)
        XCTAssertEqual(clock.label, afterSkip)

        toggle.tap()
        wait(for: [label("Pause", on: toggle)], timeout: 5)
        wait(for: [labelChanged(from: afterSkip, on: clock)], timeout: 5)
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
