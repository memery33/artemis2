import XCTest

/// Portrait and landscape. On the globe screen the path, its caption, and the
/// transport capsule stay on screen and clear of each other.
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

    func testFramesStayInsideTheScreenInBothOrientations() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let path = element(named: "orion-path", in: app)
        let caption = element(named: "globe-caption", in: app)
        let capsule = element(named: "transport-capsule", in: app)
        XCTAssertTrue(path.waitForExistence(timeout: 15))
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        XCTAssertTrue(capsule.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 8))

        assertInside(path, screen: app.frame)
        assertInside(caption, screen: app.frame)
        assertInside(capsule, screen: app.frame)
        XCTAssertFalse(path.frame.intersects(capsule.frame))
        XCTAssertFalse(caption.frame.intersects(capsule.frame))

        let column = scroller("phone-column", in: app)
        let note = element(named: "crew-note", in: app)
        reveal(note, using: column)
        assertInside(note, screen: app.frame)
        XCTAssertTrue(note.label.contains("Hansen") || note.label.contains("portrait"))
        XCTAssertFalse(note.frame.intersects(capsule.frame))

        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        let screen = window.frame
        XCTAssertTrue(path.waitForExistence(timeout: 8))
        XCTAssertTrue(caption.waitForExistence(timeout: 8))
        XCTAssertTrue(capsule.waitForExistence(timeout: 8))
        assertInside(path, screen: screen)
        assertInside(caption, screen: screen)
        assertInside(capsule, screen: screen)
        XCTAssertFalse(path.frame.intersects(capsule.frame))
        XCTAssertFalse(caption.frame.intersects(capsule.frame))
        XCTAssertFalse(app.scrollViews["landscape-rail"].exists)
        let landscapeNote = element(named: "crew-note", in: app)
        XCTAssertTrue(landscapeNote.waitForExistence(timeout: 8))
        assertInside(landscapeNote, screen: screen)
        XCTAssertFalse(landscapeNote.frame.intersects(path.frame))
        XCTAssertFalse(landscapeNote.frame.intersects(capsule.frame))
        XCTAssertGreaterThan(landscapeNote.frame.width, 160)
    }

    func testExhibitCardOpensASheet() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let column = scroller("phone-column", in: app)
        let card = element(named: "exhibit-aristarchus-plateau", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        reveal(card, using: column)
        card.tap()

        let sheet = element(named: "exhibit-sheet", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let source = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Science and Operational Focus for Aristarchus Plateau")
        ).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
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

    private func assertInside(
        _ element: XCUIElement,
        screen: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1, "\(frame) outside \(screen)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 1, "\(frame) outside \(screen)", file: file, line: line)
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
