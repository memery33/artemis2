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

    /// The longest bundled line is Hansen at 19:47:31.641Z. Begin parks there, paused.
    /// The panel shows two lines of it, still above Window 2, and the pills stay above Lines.
    func testLongestQuoteStaysAboveTheWindowPills() {
        let app = FlybyUILaunch.application(["-seekLineUTC", "2026-04-06T19:47:31.641Z"])
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let caption = element(named: "panel-caption", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let quote = caption.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "most prominent ray")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 8))
        let window = app.buttons["window-nikon"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let lines = app.buttons["lines-button"]
        XCTAssertTrue(lines.waitForExistence(timeout: 8))
        let deadline = Date().addingTimeInterval(5)
        var texts = caption.staticTexts.allElementsBoundByIndex
        while Date() < deadline, texts.count < 2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            texts = caption.staticTexts.allElementsBoundByIndex
        }
        XCTAssertGreaterThanOrEqual(texts.count, 2)
        for text in texts {
            XCTAssertGreaterThan(text.frame.height, 1)
            XCTAssertLessThanOrEqual(text.frame.maxY, window.frame.minY + 0.5)
        }
        XCTAssertLessThanOrEqual(window.frame.maxY, lines.frame.minY + 0.5)
        let frameLine = caption.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "art002e")).firstMatch
        XCTAssertTrue(frameLine.waitForExistence(timeout: 8))
        // The quote is Fraunces Italic 15. The frame line is Inter 12. Their line boxes
        // are 19 pt and 15 pt, so one quote line is 19/15 of the measured frame line.
        let frameDeadline = Date().addingTimeInterval(5)
        var frameHeight: CGFloat = frameLine.frame.height
        while Date() < frameDeadline, frameHeight <= 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            frameHeight = frameLine.frame.height
        }
        XCTAssertGreaterThan(frameHeight, 1)
        let quoteLine: CGFloat = frameHeight * CGFloat(19) / CGFloat(15)
        let twoLines: CGFloat = quoteLine * CGFloat(2) + CGFloat(8)
        XCTAssertGreaterThan(quote.frame.height, 1)
        XCTAssertLessThanOrEqual(quote.frame.height, twoLines)
        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(toggle.isHittable)
    }

    /// AX3 is UICTContentSizeCategoryAccessibilityXL (not the Swift name AccessibilityExtraLarge).
    /// AX1 AccessibilityM, AX2 AccessibilityL, AX3 AccessibilityXL, AX4 AccessibilityXXL, AX5 AccessibilityXXXL.
    /// The closed screen stays the phone's width. Once the panel is open, the scroll column
    /// and every transport control stay inside that width.
    func testAccessibilityExtraLargeKeepsTheTransportReachable() {
        assertClosedScreenStaysOnThePhone(category: "UICTContentSizeCategoryAccessibilityXL")
    }

    /// AX5, the largest Dynamic Type size. Same closed-screen and open-panel contract as AX3.
    func testAccessibilityExtraExtraExtraLargeKeepsTheTransportReachable() {
        assertClosedScreenStaysOnThePhone(category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    /// Begin parks on the longest quote. The stage must stay the screen width, and Controls
    /// must be hittable before the panel opens. The open scroll column, transport, window
    /// pills, and Lines then stay inside that same width.
    private func assertClosedScreenStaysOnThePhone(category: String) {
        let app = FlybyUILaunch.application([
            "-UIPreferredContentSizeCategoryName",
            category,
            "-seekLineUTC",
            "2026-04-06T19:47:31.641Z",
        ])
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        let screenShot = XCUIScreen.main.screenshot().image
        let screenWidth: CGFloat = screenShot.size.width
        XCTAssertEqual(app.frame.width, screenWidth, accuracy: 1.5)
        XCTAssertEqual(open.frame.width, app.frame.width, accuracy: 1.5)
        XCTAssertGreaterThanOrEqual(open.frame.minX, -0.5)
        XCTAssertLessThanOrEqual(open.frame.maxY, app.frame.maxY + 0.5)
        XCTAssertTrue(open.isHittable)
        open.tap()

        let scroll: XCUIElement = app.scrollViews["panel-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        var previous: CGRect = .zero
        var stable: Int = 0
        let opened = Date().addingTimeInterval(2)
        while Date() < opened, stable < 3 {
            let frame: CGRect = scroll.frame
            if frame.minX >= 0, frame.height > 1, abs(frame.minY - previous.minY) < 0.5 {
                stable += 1
            } else {
                stable = 0
            }
            previous = frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThanOrEqual(scroll.frame.minX, 0)
        XCTAssertLessThanOrEqual(scroll.frame.width, app.frame.width + 0.5)
        XCTAssertLessThanOrEqual(scroll.frame.maxX, app.frame.width + 0.5)

        assertWithinWindow(app.staticTexts["mission-clock"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["skip-back"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["playback-toggle"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["skip-forward"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["window-nikon"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["window-cab"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["lines-button"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["moments-button"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["about-button"], app: app, scroll: scroll)
    }

    /// Scrolls the open panel until `element` is on screen, then requires it inside the window.
    private func assertWithinWindow(_ element: XCUIElement, app: XCUIApplication, scroll: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        var attempts: Int = 0
        while attempts < 12 {
            let frame: CGRect = element.frame
            let inView: Bool = frame.minY >= -0.5 && frame.maxY <= app.frame.maxY + 0.5
            if inView, element.isHittable {
                break
            }
            if frame.minY < -0.5 {
                break
            }
            let start: XCUICoordinate = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end: XCUICoordinate = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            start.press(forDuration: 0.01, thenDragTo: end)
            attempts += 1
        }
        XCTAssertGreaterThanOrEqual(element.frame.minX, 0)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.width + 0.5)
        XCTAssertTrue(element.isHittable)
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
