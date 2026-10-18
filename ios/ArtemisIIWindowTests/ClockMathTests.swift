import XCTest
@testable import ArtemisIIWindow

final class ClockMathTests: XCTestCase {
    func testFlybyClocks() throws {
        let date = try ISO8601.parse("2026-04-06T19:33:00Z")
        let epoch = try ISO8601.parse(ClockMath.missionEpochUTC)
        XCTAssertEqual(date.timeIntervalSince(epoch), 421068, accuracy: 0.001)

        let clocks = ClockMath.format(date: date, epoch: epoch)
        XCTAssertEqual(clocks.utc, "19:33:00 UTC")
        XCTAssertEqual(clocks.eastern, "15:33:00 EDT")
        XCTAssertEqual(clocks.met, "116:57:48 MET")

        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(zone.secondsFromGMT(for: date), -4 * 3600)
        XCTAssertTrue(zone.isDaylightSavingTime(for: date))
    }

    func testEasternStandardTimeLabel() throws {
        let date = try ISO8601.parse("2026-01-15T17:00:00Z")
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertFalse(zone.isDaylightSavingTime(for: date))
        XCTAssertEqual(ClockMath.easternText(date), "12:00:00 EST")
    }

    func testMissionEpochIsZeroMET() throws {
        let epoch = try ISO8601.parse("2026-04-01T22:35:12Z")
        XCTAssertEqual(ClockMath.metText(epoch, epoch: epoch), "0:00:00 MET")
    }
}
