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

    /// Default type. The clock stays one line, and the Play circle sits inside the transport scroller.
    func testPlayToggleSitsInsideTheOpenPanel() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()
        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let toggle = app.buttons["playback-toggle"]
        let scroll = app.scrollViews["transport-scroll"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        let clock = element(named: "mission-clock", in: app)
        XCTAssertTrue(clock.waitForExistence(timeout: 8))

        let deadline = Date().addingTimeInterval(3)
        var toggleFrame = toggle.frame
        var scrollFrame = scroll.frame
        var clockFrame = clock.frame
        while Date() < deadline {
            toggleFrame = toggle.frame
            scrollFrame = scroll.frame
            clockFrame = clock.frame
            let inside = scrollFrame.height > 1
                && toggleFrame.height >= 55
                && toggleFrame.minY >= scrollFrame.minY - 0.5
                && toggleFrame.maxY <= scrollFrame.maxY + 0.5
                && toggleFrame.minX >= scrollFrame.minX - 0.5
                && toggleFrame.maxX <= scrollFrame.maxX + 0.5
                && toggleFrame.maxY <= app.frame.maxY + 0.5
                && clockFrame.height > 1
                && clockFrame.height < 26
            if inside { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThanOrEqual(toggleFrame.height, 55)
        XCTAssertGreaterThanOrEqual(toggleFrame.minY, scrollFrame.minY - 0.5)
        XCTAssertLessThanOrEqual(toggleFrame.maxY, scrollFrame.maxY + 0.5)
        XCTAssertGreaterThanOrEqual(toggleFrame.minX, scrollFrame.minX - 0.5)
        XCTAssertLessThanOrEqual(toggleFrame.maxX, scrollFrame.maxX + 0.5)
        XCTAssertLessThanOrEqual(toggleFrame.maxY, app.frame.maxY + 0.5)
        XCTAssertGreaterThan(clockFrame.height, 1)
        XCTAssertLessThan(clockFrame.height, 26)
    }

    /// AX3 is UICTContentSizeCategoryAccessibilityXL (not the Swift name AccessibilityExtraLarge).
    /// AX1 AccessibilityM, AX2 AccessibilityL, AX3 AccessibilityXL, AX4 AccessibilityXXL, AX5 AccessibilityXXXL.
    /// The closed screen stays the phone's width. Once the panel is open, the scroll column
    /// fills that width, and the transport, speaker, crew, and moment labels stay inside it.
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

        let openedToggle: XCUIElement = app.buttons["playback-toggle"]
        XCTAssertTrue(openedToggle.waitForExistence(timeout: 8))
        XCTAssertTrue(openedToggle.isHittable)

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
        XCTAssertGreaterThanOrEqual(scroll.frame.width, app.frame.width - 48)

        let clock: XCUIElement = app.descendants(matching: .any)["mission-clock"]
        assertWithinWindow(clock, app: app, scroll: scroll)
        XCTAssertTrue(clock.label.contains("UTC"))
        XCTAssertTrue(clock.label.contains("MET"))
        XCTAssertFalse(clock.label.contains("…"))

        assertWithinWindow(app.buttons["skip-back"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["playback-toggle"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["skip-forward"], app: app, scroll: scroll)

        let speaker: XCUIElement = app.staticTexts["speaker-name"]
        assertWithinWindow(speaker, app: app, scroll: scroll)
        XCTAssertEqual(speaker.label, "HANSEN")
        XCTAssertLessThanOrEqual(speaker.frame.height, speaker.frame.width)

        assertWithinWindow(app.buttons["window-nikon"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["window-cab"], app: app, scroll: scroll)
        for name in ["Wiseman", "Glover", "Koch", "Hansen"] {
            assertWithinWindow(app.buttons["crew-\(name)"], app: app, scroll: scroll)
        }
        assertWithinWindow(app.buttons["lines-button"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["moments-button"], app: app, scroll: scroll)
        assertWithinWindow(app.buttons["about-button"], app: app, scroll: scroll)
        assertStackedMoments(app: app, scroll: scroll)
    }

    /// Each moment is one button. Time and name share that stop, so VoiceOver does not land twice.
    private func assertStackedMoments(app: XCUIApplication, scroll: XCUIElement) {
        let rows: [(String, String)] = [
            ("milestone-aristarchus", "Aristarchus"),
            ("milestone-wiseman", "Aristarchus line"),
            ("milestone-reiner", "Reiner Gamma"),
            ("milestone-approach", "Closest approach"),
        ]
        let panel: XCUIElement = app.descendants(matching: .any)["control-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 4))
        for (name, title) in rows {
            let row: XCUIElement = app.buttons[name]
            reveal(row, app: app, scroll: scroll)
            assertMomentPiece(row, app: app, panelTop: panel.frame.minY)
            XCTAssertTrue(row.label.contains(title))
            XCTAssertFalse(app.descendants(matching: .any)["\(name)-time"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["\(name)-name"].exists)
        }
    }

    /// Default type. The row seeks to the nearest real Cab Cam frame and labels the gap.
    func testClosestApproachTapShowsTheLabeledGap() {
        assertClosestApproachTap(category: nil)
    }

    /// AX3 is UICTContentSizeCategoryAccessibilityXL.
    func testClosestApproachTapShowsTheLabeledGapAtAccessibility3() {
        assertClosestApproachTap(category: "UICTContentSizeCategoryAccessibilityXL")
    }

    /// The closed stage. The card and the caption stay apart at the default size, AX3, and AX5.
    func testClosestApproachCardClearsTheClosedCaption() {
        assertApproachCardClearsCaption(category: nil)
    }

    func testClosestApproachCardClearsTheClosedCaptionAtAccessibility3() {
        assertApproachCardClearsCaption(category: "UICTContentSizeCategoryAccessibilityXL")
    }

    func testClosestApproachCardClearsTheClosedCaptionAtAccessibility5() {
        assertApproachCardClearsCaption(category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    /// AX4 is UICTContentSizeCategoryAccessibilityXXL. The open card stays above the credit and the sheet.
    func testClosestApproachTapShowsTheLabeledGapAtAccessibility4() {
        assertClosestApproachTap(category: "UICTContentSizeCategoryAccessibilityXXL")
    }

    /// AX5 is UICTContentSizeCategoryAccessibilityXXXL.
    func testClosestApproachTapShowsTheLabeledGapAtAccessibility5() {
        assertClosestApproachTap(category: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    private func assertClosestApproachTap(category: String?) {
        var arguments: [String] = []
        if let category {
            arguments.append("-UIPreferredContentSizeCategoryName")
            arguments.append(category)
        }
        let app = FlybyUILaunch.application(arguments)
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()
        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        if category == nil || category == "UICTContentSizeCategoryAccessibilityXXXL" {
            assertMiniBar(app)
        }
        open.tap()
        if category == nil {
            assertRulerScrubTarget(app)
        }

        if category == nil || category == "UICTContentSizeCategoryAccessibilityXXXL" {
            assertBarApproach(app, category: category)
        }

        let row = app.buttons["milestone-approach"]
        if category != nil {
            let scroll = app.scrollViews["panel-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 8))
            reveal(row, app: app, scroll: scroll)
        } else {
            XCTAssertTrue(row.waitForExistence(timeout: 8))
        }
        XCTAssertTrue(row.isHittable)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44 - 0.5)
        row.tap()

        let gap = element(named: "approach-gap", in: app)
        XCTAssertTrue(gap.waitForExistence(timeout: 8))
        XCTAssertTrue(gap.label.contains("Closest approach: 23:00:47 UTC, 6,545 km above the Moon's 1,737.4 km mean radius (NASA/JPL Horizons)."))
        XCTAssertTrue(gap.label.contains("The nearest crew photo was taken 16 min 14 s earlier."))
        XCTAssertFalse(gap.label.contains("this clock"))
        XCTAssertFalse(gap.label.contains("Not moved"))
        let clock = element(named: "mission-clock", in: app)
        XCTAssertTrue(clock.waitForExistence(timeout: 8))
        XCTAssertTrue(clock.label.contains("22:44:33"))
        XCTAssertFalse(clock.label.contains("23:00:46"))
        let frame = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "art002e041365")
        ).firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 8))
        assertOpenApproachCardClearsCreditAndPanel(app: app, card: gap)
        if category == "UICTContentSizeCategoryAccessibilityXXL"
            || category == "UICTContentSizeCategoryAccessibilityXXXL" {
            assertApproachChevronIsHidden(app)
        }
    }

    /// Collapsed playback strip. It stays hittable, and a drag on the thin scrubber moves the clock.
    private func assertMiniBar(_ app: XCUIApplication) {
        let bar = element(named: "mini-bar", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 8))
        XCTAssertTrue(bar.isHittable)
        let play = app.buttons["mini-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 4))
        XCTAssertTrue(play.isHittable)
        XCTAssertGreaterThanOrEqual(play.frame.width, 44 - 0.5)
        XCTAssertGreaterThanOrEqual(play.frame.height, 44 - 0.5)
        play.tap()
        let scrubber = element(named: "mini-scrubber", in: app)
        XCTAssertTrue(scrubber.waitForExistence(timeout: 4))
        XCTAssertTrue(scrubber.isHittable)
        let before = scrubber.value as? String ?? ""
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let deadline = Date().addingTimeInterval(4)
        var after = scrubber.value as? String ?? ""
        while Date() < deadline {
            after = scrubber.value as? String ?? ""
            if !after.isEmpty, after != before { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(after.isEmpty)
        XCTAssertNotEqual(after, before)
        let edge = element(named: "safe-area-bottom", in: app)
        if edge.exists {
            XCTAssertLessThanOrEqual(bar.frame.maxY, edge.frame.minY + 1)
        }
    }

    /// The open ruler's drag column is at least 44 by 44.
    private func assertRulerScrubTarget(_ app: XCUIApplication) {
        let scrub = element(named: "ruler-scrub", in: app)
        XCTAssertTrue(scrub.waitForExistence(timeout: 8))
        let minimum: CGFloat = 44 - 0.5
        let deadline = Date().addingTimeInterval(3)
        var frame = scrub.frame
        while Date() < deadline {
            frame = scrub.frame
            if frame.width >= minimum, frame.height >= minimum { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThanOrEqual(frame.width, minimum)
        XCTAssertGreaterThanOrEqual(frame.height, minimum)
    }

    /// Approach sits on the bottom bar. At the default size it shares a row with About. Tapping it opens the card.
    private func assertBarApproach(_ app: XCUIApplication, category: String?) {
        let bar = app.buttons["bar-approach"]
        if category != nil {
            let scroll = app.scrollViews["panel-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 8))
            reveal(bar, app: app, scroll: scroll)
        } else {
            XCTAssertTrue(bar.waitForExistence(timeout: 8))
        }
        XCTAssertTrue(bar.isHittable)
        XCTAssertGreaterThanOrEqual(bar.frame.height, 44 - 0.5)
        XCTAssertGreaterThanOrEqual(bar.frame.minX, -0.5)
        XCTAssertLessThanOrEqual(bar.frame.maxX, app.frame.width + 0.5)
        if category == nil {
            let about = app.buttons["about-button"]
            XCTAssertTrue(about.waitForExistence(timeout: 4))
            XCTAssertEqual(bar.frame.midY, about.frame.midY, accuracy: 8)
        }
        bar.tap()
        let gap = element(named: "approach-gap", in: app)
        XCTAssertTrue(gap.waitForExistence(timeout: 8))
    }

    /// The chevron is painted as an overlay and stays out of the accessibility tree.
    private func assertApproachChevronIsHidden(_ app: XCUIApplication) {
        let down = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@ OR label == %@ OR identifier == %@",
                "Go Down",
                "chevron.down",
                "chevron.down"
            )
        )
        XCTAssertEqual(down.count, 0)
        XCTAssertFalse(app.images["Go Down"].exists)
        XCTAssertFalse(app.images["chevron.down"].exists)
    }

    /// The open card's bottom stays at or above the credit and the sheet at every text size.
    private func assertOpenApproachCardClearsCreditAndPanel(app: XCUIApplication, card: XCUIElement) {
        let credit = element(named: "photo-credit", in: app)
        let panel = element(named: "control-panel", in: app)
        XCTAssertTrue(credit.waitForExistence(timeout: 4))
        XCTAssertTrue(panel.waitForExistence(timeout: 4))
        let deadline = Date().addingTimeInterval(3)
        var cardFrame = card.frame
        var creditTop = credit.frame.minY
        var panelTop = panel.frame.minY
        while Date() < deadline {
            cardFrame = card.frame
            creditTop = credit.frame.minY
            panelTop = panel.frame.minY
            let limit = min(creditTop, panelTop)
            let clear = cardFrame.height > 1
                && credit.frame.height > 1
                && panel.frame.height > 1
                && cardFrame.maxY <= limit + 1
            if clear { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        cardFrame = card.frame
        let limit = min(credit.frame.minY, panel.frame.minY)
        XCTAssertGreaterThan(cardFrame.height, 1)
        XCTAssertGreaterThan(credit.frame.height, 1)
        XCTAssertGreaterThan(panel.frame.height, 1)
        XCTAssertLessThanOrEqual(cardFrame.maxY, limit + 1)
    }

    /// Opens closest approach, closes the panel, and requires the card to sit above the caption.
    private func assertApproachCardClearsCaption(category: String?) {
        var arguments: [String] = []
        if let category {
            arguments.append("-UIPreferredContentSizeCategoryName")
            arguments.append(category)
        }
        let app = FlybyUILaunch.application(arguments)
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()
        let open = app.buttons["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let row = app.buttons["milestone-approach"]
        if category != nil {
            let scroll = app.scrollViews["panel-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 8))
            reveal(row, app: app, scroll: scroll)
        } else {
            XCTAssertTrue(row.waitForExistence(timeout: 8))
        }
        XCTAssertTrue(row.isHittable)
        row.tap()

        let close = app.buttons["close-panel"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["open-panel"].waitForExistence(timeout: 8))

        let card = element(named: "approach-gap", in: app)
        let caption = element(named: "window-caption", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(caption.waitForExistence(timeout: 8))

        let checksIsland = category == nil || category == "UICTContentSizeCategoryAccessibilityXXXL"
        let island = element(named: "safe-area-top", in: app)
        if checksIsland {
            XCTAssertTrue(island.waitForExistence(timeout: 4))
        }
        let deadline = Date().addingTimeInterval(3)
        var cardFrame = card.frame
        var captionFrame = caption.frame
        while Date() < deadline {
            cardFrame = card.frame
            captionFrame = caption.frame
            let overlap = cardFrame.intersection(captionFrame)
            let belowIsland = !checksIsland || cardFrame.minY >= island.frame.minY - 0.5
            let apart = cardFrame.height > 1
                && captionFrame.height > 1
                && cardFrame.maxY <= captionFrame.minY + 1
                && belowIsland
                && (overlap.isNull || overlap.width < 1 || overlap.height < 1)
            if apart { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let overlap = cardFrame.intersection(captionFrame)
        XCTAssertGreaterThan(cardFrame.width, 1)
        XCTAssertGreaterThan(cardFrame.height, 1)
        XCTAssertGreaterThan(captionFrame.width, 1)
        XCTAssertGreaterThan(captionFrame.height, 1)
        XCTAssertGreaterThanOrEqual(cardFrame.minX, -0.5)
        XCTAssertLessThanOrEqual(cardFrame.maxX, app.frame.width + 0.5)
        XCTAssertGreaterThanOrEqual(captionFrame.minX, -0.5)
        XCTAssertLessThanOrEqual(captionFrame.maxX, app.frame.width + 0.5)
        XCTAssertLessThanOrEqual(cardFrame.maxY, captionFrame.minY + 1)
        XCTAssertTrue(overlap.isNull || overlap.width < 1 || overlap.height < 1)
        if category == nil || category == "UICTContentSizeCategoryAccessibilityXXXL" {
            assertApproachCardClearsTheTopSafeArea(app: app, cardFrame: cardFrame)
        }
        if category == "UICTContentSizeCategoryAccessibilityXXXL" {
            assertCaptionClearsControls(app: app, card: card, caption: caption)
            assertApproachChevronIsHidden(app)
        }
    }

    /// AX5. The frame id and the credit stay above the Controls strip and on the phone.
    private func assertCaptionClearsControls(app: XCUIApplication, card: XCUIElement, caption: XCUIElement) {
        let controls = app.buttons["open-panel"]
        let frameIDs = app.descendants(matching: .any).matching(identifier: "frame-id")
        let frameID = caption.descendants(matching: .any)["frame-id"]
        let credit = caption.descendants(matching: .any)["photo-credit"]
        XCTAssertTrue(controls.waitForExistence(timeout: 4))
        XCTAssertTrue(frameID.waitForExistence(timeout: 4))
        XCTAssertTrue(credit.waitForExistence(timeout: 4))
        XCTAssertEqual(frameIDs.count, 1)
        let deadline = Date().addingTimeInterval(3)
        var controlsTop = controls.frame.minY
        var cardFrame = card.frame
        var captionFrame = caption.frame
        var idFrame = frameID.frame
        var creditFrame = credit.frame
        while Date() < deadline {
            controlsTop = controls.frame.minY
            cardFrame = card.frame
            captionFrame = caption.frame
            idFrame = frameID.frame
            creditFrame = credit.frame
            let limit = controlsTop + 1
            let bottom = app.frame.maxY + 0.5
            let clear = controls.frame.height > 1
                && captionFrame.height > 1
                && idFrame.height > 1
                && creditFrame.height > 1
                && captionFrame.maxY <= limit
                && idFrame.maxY <= limit
                && creditFrame.maxY <= limit
                && cardFrame.maxY <= bottom
                && captionFrame.maxY <= bottom
                && idFrame.maxY <= bottom
                && creditFrame.maxY <= bottom
                && cardFrame.maxY <= captionFrame.minY + 1
            if clear { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let limit = controlsTop + 1
        let bottom = app.frame.maxY + 0.5
        XCTAssertGreaterThan(controls.frame.height, 1)
        XCTAssertLessThanOrEqual(cardFrame.maxY, captionFrame.minY + 1)
        XCTAssertLessThanOrEqual(captionFrame.maxY, limit)
        XCTAssertLessThanOrEqual(idFrame.maxY, limit)
        XCTAssertLessThanOrEqual(creditFrame.maxY, limit)
        XCTAssertLessThanOrEqual(cardFrame.maxY, bottom)
        XCTAssertLessThanOrEqual(captionFrame.maxY, bottom)
        XCTAssertLessThanOrEqual(idFrame.maxY, bottom)
        XCTAssertLessThanOrEqual(creditFrame.maxY, bottom)
        XCTAssertGreaterThanOrEqual(idFrame.minY, -0.5)
        XCTAssertGreaterThanOrEqual(creditFrame.minY, -0.5)
    }

    /// The card starts at or below the safe-area mark. On a Face ID phone the mark and the card
    /// also clear 44 pt, so a zero inset cannot satisfy the check by moving both to the top.
    private func assertApproachCardClearsTheTopSafeArea(app: XCUIApplication, cardFrame: CGRect) {
        let island = element(named: "safe-area-top", in: app)
        XCTAssertTrue(island.waitForExistence(timeout: 4))
        XCTAssertGreaterThan(island.frame.height, 0)
        XCTAssertGreaterThanOrEqual(cardFrame.minY, island.frame.minY - 0.5)
        let bar = app.statusBars.firstMatch
        if bar.exists, bar.frame.height > 1, bar.frame.maxY < app.frame.height * 0.5 {
            XCTAssertGreaterThanOrEqual(cardFrame.minY, bar.frame.maxY - 0.5)
            XCTAssertGreaterThanOrEqual(island.frame.minY, bar.frame.minY - 0.5)
        }
        if app.frame.height >= 812 {
            XCTAssertGreaterThanOrEqual(island.frame.minY, 44)
            XCTAssertGreaterThanOrEqual(cardFrame.minY, 44)
        }
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication, scroll: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        var attempts: Int = 0
        while attempts < 16 {
            let frame: CGRect = element.frame
            let inColumn: Bool = frame.minY >= scroll.frame.minY - 0.5 && frame.maxY <= app.frame.maxY - 4 && frame.height > 1
            if inColumn {
                break
            }
            if frame.minY < scroll.frame.minY - 0.5 {
                break
            }
            let start: XCUICoordinate = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end: XCUICoordinate = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            start.press(forDuration: 0.01, thenDragTo: end)
            attempts += 1
        }
    }

    private func assertMomentPiece(_ element: XCUIElement, app: XCUIApplication, panelTop: CGFloat) {
        let frame: CGRect = element.frame
        XCTAssertGreaterThan(frame.width, 1)
        XCTAssertGreaterThan(frame.height, 1)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.maxX, app.frame.width + 0.5)
        XCTAssertGreaterThanOrEqual(frame.minY, panelTop - 0.5)
    }

    /// Scrolls the open panel until `element` is on screen, then requires it inside the window.
    private func assertWithinWindow(_ element: XCUIElement, app: XCUIApplication, scroll: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        var attempts: Int = 0
        while attempts < 16 {
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
        assertSquareHitTarget(app.buttons["bar-approach"], minimumSide: minimumSide)
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
