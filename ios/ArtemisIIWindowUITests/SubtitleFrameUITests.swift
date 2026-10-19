import XCTest

/// The cabin quote is two stacked lines. Their frames stay apart, including at
/// 19:33:15–19:33:18 UTC where the plateau zoom line is current.
@MainActor
final class SubtitleFrameUITests: XCTestCase {
    func testAtMostOneSubtitleOccupiesAFrame() {
        let app = FlybyUILaunch.application()
        app.launch()
        let begin = app.buttons["Begin Flyby"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15))
        begin.tap()

        let toggle = app.buttons["playback-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: toggle)
        _ = XCTWaiter.wait(for: [playing], timeout: 5)
        if toggle.label == "Pause" {
            toggle.tap()
        }
        let clock = app.descendants(matching: .any)["mission-clock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 8))
        park(clock, in: app, from: 19 * 3600 + 33 * 60 + 15, through: 19 * 3600 + 33 * 60 + 18)

        let dive = app.buttons["dive-button"]
        XCTAssertTrue(dive.waitForExistence(timeout: 8))
        dive.tap()

        let zoom = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Centered image of the plateau in full zoom")
        ).firstMatch
        XCTAssertTrue(zoom.waitForExistence(timeout: 8))

        let lines = app.descendants(matching: .any).matching(identifier: "subtitle-line")
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 8))
        var frames: [CGRect] = []
        for index in 0..<lines.count {
            let frame = lines.element(boundBy: index).frame
            guard frame.width > 1, frame.height > 1 else { continue }
            frames.append(frame)
        }
        XCTAssertGreaterThanOrEqual(frames.count, 1)
        for left in 0..<frames.count {
            for right in (left + 1)..<frames.count {
                let hit = frames[left].intersection(frames[right])
                XCTAssertLessThanOrEqual(hit.width, 1, "\(frames[left]) overlaps \(frames[right])")
                XCTAssertLessThanOrEqual(hit.height, 1, "\(frames[left]) overlaps \(frames[right])")
            }
        }
        let missing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "frame was taken at this time"))
        for index in 0..<missing.count {
            let intruder = missing.element(boundBy: index)
            guard intruder.exists, intruder.frame.width > 1, intruder.frame.height > 1 else { continue }
            for frame in frames {
                let hit = intruder.frame.intersection(frame)
                XCTAssertLessThanOrEqual(hit.width, 1, "\(intruder.label) overlaps \(frame)")
                XCTAssertLessThanOrEqual(hit.height, 1, "\(intruder.label) overlaps \(frame)")
            }
        }
    }

    private func park(_ clock: XCUIElement, in app: XCUIApplication, from lower: Int, through upper: Int) {
        for _ in 0..<8 {
            guard let seconds = utcSeconds(clock.label) else { return }
            if seconds >= lower, seconds <= upper { return }
            let before = clock.label
            if seconds < lower {
                app.buttons["skip-forward"].tap()
            } else {
                app.buttons["skip-back"].tap()
            }
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@", before),
                object: clock
            )
            _ = XCTWaiter.wait(for: [changed], timeout: 4)
        }
    }

    private func utcSeconds(_ label: String) -> Int? {
        guard let match = label.range(of: #"\d{2}:\d{2}:\d{2}"#, options: .regularExpression) else { return nil }
        let clock = label[match]
        let parts = clock.split(separator: ":")
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]) else { return nil }
        return hour * 3600 + minute * 60 + second
    }
}
