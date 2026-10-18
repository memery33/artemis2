import XCTest
@testable import ArtemisIIWindow

final class FrameSelectionTests: XCTestCase {
    private var timeline: Timeline!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: FrameSelectionTests.self).url(forResource: "timeline", withExtension: "json"))
        timeline = try Timeline(data: Data(contentsOf: url))
    }

    func testWindow2PairsStayOnLabelTime() throws {
        let before = try pair("2026-04-06T19:33:10Z", .nikon)
        XCTAssertNil(before.current)
        XCTAssertEqual(before.next?.nasaID, "art002e016184")

        let early = try pair("2026-04-06T19:33:30Z", .nikon)
        XCTAssertEqual(early.current?.nasaID, "art002e016184")
        XCTAssertEqual(early.next?.nasaID, "art002e009611")

        let flyby = try pair("2026-04-06T19:40:18Z", .nikon)
        XCTAssertEqual(flyby.current?.nasaID, "art002e009876")
        XCTAssertEqual(flyby.current?.utc, "2026-04-06T19:39:53.670Z")
        XCTAssertEqual(flyby.next?.nasaID, "art002e009881")

        let current = try XCTUnwrap(flyby.current)
        let next = try XCTUnwrap(flyby.next)
        let landed = FrameSelection.crossfade(now: next.date, current: current.date, next: next.date)
        XCTAssertEqual(landed.mix, 1, accuracy: 0.0001)
        XCTAssertTrue(landed.dominantIsNext)
        let approaching = FrameSelection.crossfade(
            now: next.date.addingTimeInterval(-0.05),
            current: current.date,
            next: next.date
        )
        XCTAssertLessThan(approaching.mix, 1)

        let stale = try pair("2026-04-06T20:03:00Z", .nikon)
        XCTAssertNil(stale.current)
        XCTAssertNil(stale.next)
    }

    func testWindow3KeepsOlderCabFrameAndCabinCardStaysOffTheGlass() throws {
        let cab = try pair("2026-04-06T19:40:00Z", .cab)
        XCTAssertEqual(cab.current?.nasaID, "art002e041322")
        XCTAssertEqual(cab.current?.utc, "2026-04-06T19:34:44.000Z")

        let during = FrameSelection.cabinCard(at: try date("2026-04-06T19:33:05Z"), frames: timeline.frames)
        XCTAssertEqual(during?.nasaID, "art002e016183")
        let after = FrameSelection.cabinCard(at: try date("2026-04-06T19:33:20Z"), frames: timeline.frames)
        XCTAssertNil(after)

        for side in [WindowSide.nikon, WindowSide.cab] {
            let rows = FrameSelection.frames(timeline.frames, window: side)
            XCTAssertFalse(rows.contains { $0.nasaID == "art002e016183" })
        }
    }

    func testMapOmitsHertzsprung() throws {
        let names = Set(MapProjection.geographicTargets(timeline.targets).map(\.name))
        XCTAssertEqual(
            names,
            Set([
                "Glushko Crater",
                "Ohm Crater",
                "Aristarchus Plateau",
                "Reiner Gamma",
                "Orientale Basin",
                "Vavilov Crater",
            ])
        )
        XCTAssertFalse(names.contains("Hertzsprung Basin"))
        let ohm = try XCTUnwrap(MapProjection.point(lon: 246.22, lat: 18.32, width: 120, height: 85))
        XCTAssertEqual(ohm.x, 36.22, accuracy: 0.001)
        XCTAssertEqual(ohm.y, 26.68, accuracy: 0.001)
        XCTAssertNil(MapProjection.point(lon: 0, lat: 0, width: 120, height: 85))
    }

    private func pair(_ utc: String, _ window: WindowSide) throws -> FramePair {
        FrameSelection.visiblePair(at: try date(utc), window: window, frames: timeline.frames)
    }

    private func date(_ utc: String) throws -> Date {
        try ISO8601.parse(utc)
    }
}
