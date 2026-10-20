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

    /// The speaker line and the quote both stay on screen, above the Window 2 control.
    /// That control sits at the top of the pinned row, so a caption that has
    /// scrolled under it cannot pass by still sitting above the Lines button.
    func testPanelCaptionStaysAboveTheFold() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let caption = element(named: "panel-caption", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let window = app.buttons["window-nikon"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let deadline = Date().addingTimeInterval(5)
        var texts = caption.staticTexts.allElementsBoundByIndex
        while Date() < deadline, texts.count < 2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            texts = caption.staticTexts.allElementsBoundByIndex
        }
        XCTAssertGreaterThanOrEqual(texts.count, 2)
        for text in texts {
            XCTAssertGreaterThan(text.frame.height, 1)
            XCTAssertGreaterThanOrEqual(text.frame.minY, 0)
            XCTAssertLessThanOrEqual(text.frame.maxY, app.frame.height)
            XCTAssertLessThanOrEqual(text.frame.maxY, window.frame.minY + 0.5)
        }
    }

    /// Lines, Moments, and About sit on the safe-area edge, and those controls are at least 44 by 44.
    func testAboutClearsTheHomeIndicatorAndControlsAre44Points() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let about = app.buttons["about-button"]
        XCTAssertTrue(about.waitForExistence(timeout: 8))
        let edge = element(named: "safe-area-bottom", in: app)
        XCTAssertTrue(edge.waitForExistence(timeout: 8))
        let minimumSide = 44 - 0.01
        // XCUIElement does not resolve frame.size through NSPredicate, so poll the frame itself.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let frame = about.frame
            if frame.width >= minimumSide, frame.height >= minimumSide { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let inset = app.frame.maxY - edge.frame.maxY
        XCTAssertGreaterThanOrEqual(inset, 20)
        XCTAssertLessThanOrEqual(about.frame.maxY, app.frame.height - inset + 0.01)
        assertSquareHitTarget(about, minimumSide: minimumSide)
        assertSquareHitTarget(app.buttons["lines-button"], minimumSide: minimumSide)
        assertSquareHitTarget(app.buttons["moments-button"], minimumSide: minimumSide)
        for name in ["Wiseman", "Glover", "Koch", "Hansen"] {
            assertSquareHitTarget(app.buttons["crew-\(name)"], minimumSide: minimumSide)
        }
    }

    private func assertSquareHitTarget(_ element: XCUIElement, minimumSide: CGFloat) {
        XCTAssertTrue(element.exists)
        XCTAssertGreaterThanOrEqual(element.frame.width, minimumSide)
        XCTAssertGreaterThanOrEqual(element.frame.height, minimumSide)
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
