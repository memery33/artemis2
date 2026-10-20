import XCTest

/// The crew credit is a visible element on the opening photograph, the flyby frame, and a crater.
@MainActor
final class PhotoCreditUITests: XCTestCase {
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

    func testCreditIsPresentOnTheOpeningPlaybackAndCrater() {
        let app = FlybyUILaunch.application()
        app.launch()

        let gateCredits = app.descendants(matching: .any).matching(identifier: "photo-credit")
        let gateCredit = gateCredits.firstMatch
        XCTAssertTrue(gateCredit.waitForExistence(timeout: 15))
        XCTAssertEqual(gateCredits.count, 1)
        XCTAssertEqual(gateCredit.label, "Credit: NASA/Artemis II Crew")

        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let caption = app.descendants(matching: .any)["window-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        let windowCredit = caption.descendants(matching: .any).matching(identifier: "photo-credit").firstMatch
        XCTAssertTrue(windowCredit.waitForExistence(timeout: 5))
        XCTAssertEqual(windowCredit.label, "Credit: NASA/Artemis II Crew")

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()
        let crater = app.buttons["milestone-aristarchus"]
        XCTAssertTrue(crater.waitForExistence(timeout: 8))
        crater.tap()

        let page = app.descendants(matching: .any)["crater-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        let pageCredit = page.descendants(matching: .any).matching(identifier: "photo-credit").firstMatch
        XCTAssertTrue(pageCredit.waitForExistence(timeout: 8))
        XCTAssertEqual(pageCredit.label, "Credit: NASA/Artemis II Crew")
    }
}
