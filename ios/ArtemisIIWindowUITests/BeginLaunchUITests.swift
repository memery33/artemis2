import XCTest

/// Release scheme `ArtemisIIWindowRelease`. The begin-button trap is a Release
/// isolation check inside the Now Playing artwork handler.
@MainActor
final class BeginLaunchUITests: XCTestCase {
    func testTapToBeginStaysRunning() {
        let app = XCUIApplication()
        app.launch()
        let begin = app.buttons["Tap to begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()
        // Now Playing asks for artwork on a background queue after begin.
        let hold = expectation(description: "artwork handler window")
        hold.isInverted = true
        wait(for: [hold], timeout: 12)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
