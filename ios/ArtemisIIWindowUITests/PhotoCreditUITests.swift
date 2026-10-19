import XCTest

/// The crew credit has to be a visible element on each photograph, not only in About.
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

    func testCreditIsPresentOnTheGateWindowCabinAndExhibit() {
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

        let column = scroller("phone-column", in: app)
        let caption = element(named: "window-caption", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        let windowCredit = credit(in: caption)
        XCTAssertTrue(windowCredit.waitForExistence(timeout: 5))
        XCTAssertEqual(windowCredit.label, "Credit: NASA/Artemis II Crew")
        reveal(caption, using: column)

        // art002e016183 is held for nine seconds starting at 19:33:03.910 UTC.
        let cabin = element(named: "cabin-card", in: app)
        XCTAssertTrue(cabin.waitForExistence(timeout: 12))
        let cabinCredit = credit(in: cabin)
        XCTAssertTrue(cabinCredit.waitForExistence(timeout: 5))
        XCTAssertEqual(cabinCredit.label, "Credit: NASA/Artemis II Crew")
        reveal(cabin, using: column)

        let card = element(named: "exhibit-aristarchus-plateau", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        reveal(card, using: column)
        let cardCredit = creditBelow(card, in: app, timeout: 8)
        XCTAssertTrue(cardCredit.exists)
        XCTAssertEqual(cardCredit.label, "Credit: NASA/Artemis II Crew")
        card.tap()
        let sheet = element(named: "exhibit-sheet", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let sheetCredit = credit(in: sheet)
        XCTAssertTrue(sheetCredit.waitForExistence(timeout: 8))
        XCTAssertEqual(sheetCredit.label, "Credit: NASA/Artemis II Crew")
        app.buttons["Done"].tap()

        let dive = app.buttons["dive-button"]
        reveal(dive, using: column)
        XCTAssertTrue(dive.waitForExistence(timeout: 8))
        dive.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeCaption = element(named: "window-caption", in: app)
        XCTAssertTrue(landscapeCaption.waitForExistence(timeout: 8))
        let landscapeCredit = credit(in: landscapeCaption)
        XCTAssertTrue(landscapeCredit.waitForExistence(timeout: 5))
        XCTAssertEqual(landscapeCredit.label, "Credit: NASA/Artemis II Crew")
        XCTAssertGreaterThan(landscapeCredit.frame.width, 1)
        XCTAssertGreaterThan(landscapeCredit.frame.height, 1)
    }

    private func credit(in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any).matching(identifier: "photo-credit").firstMatch
    }

    /// The exhibit credit sits under the button, so it is not one of the button's descendants.
    private func creditBelow(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var found = app.descendants(matching: .any)["photo-credit-missing"]
        while Date() < deadline {
            if let match = nearestCredit(below: element, in: app), match.exists {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        if let match = nearestCredit(below: element, in: app) {
            found = match
        }
        return found
    }

    private func nearestCredit(below element: XCUIElement, in app: XCUIApplication) -> XCUIElement? {
        let matches = app.descendants(matching: .any).matching(identifier: "photo-credit")
        let frame = element.frame
        var found: XCUIElement?
        var bestGap = CGFloat.greatestFiniteMagnitude
        for index in 0..<matches.count {
            let candidate = matches.element(boundBy: index)
            guard candidate.exists else { continue }
            let credit = candidate.frame
            let gap = credit.minY - frame.maxY
            let aligned = abs(credit.minX - frame.minX) < 48
            if aligned, gap >= -4, gap < 80, gap < bestGap {
                bestGap = gap
                found = candidate
            }
        }
        return found
    }

    private func element(named identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scroller(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let typed = app.scrollViews[identifier]
        if typed.waitForExistence(timeout: 5) {
            return typed
        }
        let any = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(any.waitForExistence(timeout: 5))
        return any
    }

    private func reveal(_ element: XCUIElement, using scroller: XCUIElement) {
        for _ in 0..<12 {
            if contains(element.frame, in: scroller.frame.insetBy(dx: -1, dy: -1)) {
                return
            }
            let frame = element.frame
            let bounds = scroller.frame
            let start: CGVector
            let end: CGVector
            if frame.maxY > bounds.maxY + 1 {
                start = CGVector(dx: 0.5, dy: 0.75)
                end = CGVector(dx: 0.5, dy: 0.35)
            } else if frame.minY < bounds.minY - 1 {
                start = CGVector(dx: 0.5, dy: 0.35)
                end = CGVector(dx: 0.5, dy: 0.75)
            } else {
                return
            }
            scroller.coordinate(withNormalizedOffset: start)
                .press(forDuration: 0.05, thenDragTo: scroller.coordinate(withNormalizedOffset: end))
        }
    }

    private func contains(_ frame: CGRect, in screen: CGRect) -> Bool {
        frame.minX >= screen.minX - 1
            && frame.minY >= screen.minY - 1
            && frame.maxX <= screen.maxX + 1
            && frame.maxY <= screen.maxY + 1
            && frame.width > 1
            && frame.height > 1
    }
}
