import XCTest
@testable import ArtemisIIWindow

final class TimelineTests: XCTestCase {
    private var timeline: Timeline!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: TimelineTests.self).url(forResource: "timeline", withExtension: "json"))
        timeline = try Timeline(data: Data(contentsOf: url))
    }

    func testParseKeepsShippedUTC() throws {
        XCTAssertEqual(timeline.version, 1)
        XCTAssertEqual(timeline.missionStart.utc, "2026-04-01T22:35:12Z")
        let opener = try XCTUnwrap(timeline.segments.first { $0.nasaID == "art002a000021" })
        XCTAssertEqual(opener.startUTC, "2026-04-06T19:33:01.758Z")
        XCTAssertTrue(timeline.lines.contains { $0.text == "Alright team, we're diving back into Aristarchus." })
        XCTAssertEqual(timeline.frames.count, 63)
        XCTAssertEqual(timeline.segments.count, 6)
        XCTAssertEqual(timeline.licenses.count, 5)
        let cab = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e041322" })
        XCTAssertEqual(cab.utc, "2026-04-06T19:34:44.000Z")
    }

    func testPointingCaveatAndSilentCabRun() {
        XCTAssertFalse(timeline.pointing.available)
        XCTAssertTrue(timeline.pointing.note.contains("CK/FK/SCLK"))
        XCTAssertEqual(timeline.attribution.credit, "Credit: NASA/Artemis II Crew")
        XCTAssertTrue(timeline.cabRun?.note?.contains("silent") == true)
        XCTAssertFalse(timeline.targets.contains { $0.name == "Hertzsprung Basin" && $0.geographic })
    }
}
