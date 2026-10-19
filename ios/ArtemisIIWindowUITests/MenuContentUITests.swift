import XCTest

/// The more menu has to open real dive content, including while audio is playing.
@MainActor
final class MenuContentUITests: XCTestCase {
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

    func testEachMenuItemOpensRealContentWhilePlaying() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Pause"),
            object: toggle
        )
        _ = XCTWaiter.wait(for: [playing], timeout: 8)
        XCTAssertEqual(toggle.label, "Pause")

        tapMenu("Dive into the window", in: app)
        assertRealDiveContent(app)
        XCTAssertTrue(app.buttons["surface-button"].waitForExistence(timeout: 4))

        tapMenu("Back to the Moon", in: app)
        XCTAssertTrue(app.buttons["dive-button"].waitForExistence(timeout: 4))

        tapMenu("Window 2", in: app)
        assertRealDiveContent(app)
        XCTAssertTrue(app.buttons["surface-button"].waitForExistence(timeout: 4))

        tapMenu("Back to the Moon", in: app)
        tapMenu("Window 3", in: app)
        assertRealDiveContent(app)
        XCTAssertTrue(app.buttons["surface-button"].waitForExistence(timeout: 4))

        tapMenu("Cab run", in: app)
        assertRealDiveContent(app)

        tapMenu("Crew, Glover", in: app)
        openMenu(in: app)
        let hansen = menuItem("Crew, Hansen", in: app)
        XCTAssertTrue(hansen.waitForExistence(timeout: 4))
        hansen.tap()

        tapMenu("Lines", in: app)
        let transcript = app.navigationBars["Transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 6) || app.staticTexts["Transcript"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()

        tapMenu("Spatial", in: app)
        openMenu(in: app)
        let spatialOn = menuItem("Spatial on", in: app)
        XCTAssertTrue(spatialOn.waitForExistence(timeout: 4))
        spatialOn.tap()

        tapMenu("Flyby", in: app)
        assertRealDiveContent(app)

        tapMenu("Back to the Moon", in: app)
        XCTAssertTrue(app.buttons["dive-button"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.buttons["playback-toggle"].label, "Pause")
    }

    private func assertRealDiveContent(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let photo = app.descendants(matching: .any)["window-photo"]
        let empty = app.descendants(matching: .any)["window-empty"]
        let standIn = app.descendants(matching: .any)["window-stand-in"]
        let found = photo.waitForExistence(timeout: 8)
            || standIn.waitForExistence(timeout: 2)
            || empty.waitForExistence(timeout: 2)
        XCTAssertTrue(
            found,
            "Dive view has no photo, stand-in label, or no-frame message",
            file: file,
            line: line
        )
        if photo.exists {
            XCTAssertGreaterThan(photo.frame.width, 40, file: file, line: line)
            XCTAssertGreaterThan(photo.frame.height, 40, file: file, line: line)
            let subtitle = app.descendants(matching: .any).matching(identifier: "subtitle-line").firstMatch
            if subtitle.exists, subtitle.frame.height > 1, photo.frame.height > 1 {
                let overlap = photo.frame.intersection(subtitle.frame)
                XCTAssertLessThan(overlap.height, photo.frame.height * 0.85, file: file, line: line)
            }
        }
        if empty.exists {
            XCTAssertGreaterThan(empty.frame.width, 1, file: file, line: line)
            XCTAssertGreaterThan(empty.frame.height, 1, file: file, line: line)
        }
        if standIn.exists {
            XCTAssertTrue(standIn.label.contains("Taken"), file: file, line: line)
            XCTAssertTrue(standIn.label.contains("UTC"), file: file, line: line)
            XCTAssertGreaterThan(standIn.frame.height, 1, file: file, line: line)
        }
    }

    private func openMenu(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let more = app.buttons["more-controls"]
        XCTAssertTrue(more.waitForExistence(timeout: 8), file: file, line: line)
        more.tap()
    }

    private func tapMenu(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let item = menuItem(title, in: app)
        if !item.exists {
            openMenu(in: app, file: file, line: line)
        }
        let opened = menuItem(title, in: app)
        XCTAssertTrue(opened.waitForExistence(timeout: 4), "Missing menu item \(title)", file: file, line: line)
        opened.tap()
    }

    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[title]
        if button.exists { return button }
        return app.menuItems[title]
    }
}
