import XCTest

/// Release scheme `ArtemisIIWindowRelease`. The begin-button trap is a Release
/// isolation check inside the Now Playing artwork handler.
@MainActor
final class BeginLaunchUITests: XCTestCase {
    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            FlybyUILaunch.endActivities()
        }
        super.tearDown()
    }

    func testTapToBeginStaysRunning() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()
        // Now Playing asks for artwork on a background queue after begin.
        let hold = expectation(description: "artwork handler window")
        hold.isInverted = true
        wait(for: [hold], timeout: 12)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSeekToEndShowsTheEndCard() {
        let app = FlybyUILaunch.application(["-seekToEnd"])
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()
        let card = app.descendants(matching: .any)["end-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(card.staticTexts["End of this span"].waitForExistence(timeout: 15))
    }
}
