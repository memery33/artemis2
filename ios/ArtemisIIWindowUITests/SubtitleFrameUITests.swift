import XCTest

/// The documentary caption is one compact block. It does not cover the photograph,
/// and an empty black pane is not drawn in its place.
@MainActor
final class SubtitleFrameUITests: XCTestCase {
    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            FlybyUILaunch.endActivities()
        }
        super.tearDown()
    }

    func testCaptionStaysCompactOnARealFrame() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let caption = app.descendants(matching: .any)["window-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(caption.frame.width, 1)
        XCTAssertGreaterThan(caption.frame.height, 1)
        XCTAssertLessThan(caption.frame.width, app.frame.width - 40)
        XCTAssertLessThan(caption.frame.maxX, app.frame.maxX)
        XCTAssertLessThan(caption.frame.maxY, app.frame.maxY)

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

        let credit = caption.descendants(matching: .any).matching(identifier: "photo-credit").firstMatch
        XCTAssertTrue(credit.waitForExistence(timeout: 5))
        XCTAssertEqual(credit.label, "Credit: NASA/Artemis II Crew")
    }
}
