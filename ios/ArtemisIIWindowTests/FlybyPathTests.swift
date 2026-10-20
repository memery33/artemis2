import XCTest
@testable import ArtemisIIWindow

final class FlybyPathTests: XCTestCase {
    private var document: FlybyDocument!
    private var samples: [PathSample]!

    override func setUpWithError() throws {
        document = try XCTUnwrap(FlybyEphemeris.load())
        samples = FlybyEphemeris.samples(in: document)
        XCTAssertEqual(samples.count, document.samples.count)
    }

    func testBundledHorizonsTableCoversTheFlyby() {
        XCTAssertEqual(document.frame, "MOON_ME")
        XCTAssertTrue(document.query.contains("COMMAND=301"))
        XCTAssertTrue(document.query.contains("CENTER=500@-1024"))
        XCTAssertTrue(document.query.contains("QUANTITIES=14,20"))
        XCTAssertFalse(document.query.contains("REF_PLANE=BODY EQUATOR"))
        XCTAssertEqual(document.radiusKm, 1737.4)
        XCTAssertGreaterThan(samples.count, 400)
        XCTAssertEqual(document.samples.first?.t, "2026-04-06T18:00:00Z")
        XCTAssertEqual(document.samples.last?.t, "2026-04-07T02:00:00Z")
    }

    /// Sub-observer point in the IAU MOON_ME frame. Horizons prints 253.089630°E
    /// (−106.91037°) and 1.60578°N at 19:40 UT, and 179.492308°E, −2.607641° at the minimum range.
    func testBodyFixedLongitudeMatchesTheSubObserverPoint() throws {
        let target = Self.utc("2026-04-06T19:40:00Z")
        let at1940 = try XCTUnwrap(samples.min {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        })
        XCTAssertEqual(at1940.date.timeIntervalSince(target), 0, accuracy: 1)
        XCTAssertEqual(Self.longitudeEast(at1940), -106.91037, accuracy: 0.05)
        XCTAssertEqual(Self.latitude(at1940), 1.60578, accuracy: 0.05)
        let approach = try XCTUnwrap(FlybyPath.closestApproach(samples, radiusKm: document.radiusKm))
        let lowest = try XCTUnwrap(samples.min { $0.rangeKm < $1.rangeKm })
        XCTAssertEqual(approach.date.timeIntervalSince(lowest.date), 0, accuracy: 60)
        XCTAssertEqual(Self.longitudeEast(lowest), 179.492308, accuracy: 0.05)
        XCTAssertEqual(Self.latitude(lowest), -2.607641, accuracy: 0.05)
    }

    func testClosestApproachUsesTheSampleSpacing() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let rows = [
            PathSample(date: start, x: 0, y: 0, z: 0, rangeKm: 10),
            PathSample(date: start.addingTimeInterval(120), x: 0, y: 0, z: 0, rangeKm: 8),
            PathSample(date: start.addingTimeInterval(240), x: 0, y: 0, z: 0, rangeKm: 9)
        ]
        let approach = try XCTUnwrap(FlybyPath.closestApproach(rows, radiusKm: 1))
        // Vertex is 1/6 of a sample past the middle. The file step is 120 s, not 60.
        XCTAssertEqual(approach.date.timeIntervalSince(start), 140, accuracy: 0.01)
    }

    private static func utc(_ text: String) -> Date {
        let clock = ISO8601DateFormatter()
        clock.formatOptions = [.withInternetDateTime]
        return clock.date(from: text) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private static func longitudeEast(_ sample: PathSample) -> Double {
        longitudeEast(x: sample.x, y: sample.y)
    }

    private static func longitudeEast(x: Double, y: Double) -> Double {
        atan2(y, x) * 180 / .pi
    }

    private static func latitude(_ sample: PathSample) -> Double {
        atan2(sample.z, hypot(sample.x, sample.y)) * 180 / .pi
    }

    func testPathFractionRoundTripsToTheSameTime() {
        let lengths = FlybyPath.arcLengths(samples)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.1) {
            let date = FlybyPath.date(atFraction: fraction, samples: samples, lengths: lengths)
            let back = FlybyPath.fraction(at: date, samples: samples, lengths: lengths)
            XCTAssertEqual(back, fraction, accuracy: 0.002)
            let again = FlybyPath.date(atFraction: back, samples: samples, lengths: lengths)
            XCTAssertEqual(again.timeIntervalSince(date), 0, accuracy: 1)
        }
    }

    func testDraggingAlongThePathMovesTimeForward() {
        let lengths = FlybyPath.arcLengths(samples)
        var previous = samples[0].date
        for step in 1...20 {
            let date = FlybyPath.date(atFraction: Double(step) / 20, samples: samples, lengths: lengths)
            XCTAssertGreaterThan(date, previous)
            previous = date
        }
        XCTAssertEqual(FlybyPath.date(atFraction: 0, samples: samples), samples[0].date)
        XCTAssertEqual(FlybyPath.date(atFraction: 1, samples: samples), samples[samples.count - 1].date)
    }

    func testMilestoneTimesLandOnThePath() throws {
        let url = try XCTUnwrap(Bundle(for: FlybyPathTests.self).url(forResource: "timeline", withExtension: "json"))
        let timeline = try Timeline(data: Data(contentsOf: url))
        let rows = MilestoneList.derive(timeline)
        let first = try XCTUnwrap(samples.first).date
        let last = try XCTUnwrap(samples.last).date
        let inside = rows.filter { $0.date >= first && $0.date <= last }
        XCTAssertGreaterThan(inside.count, 10)
        for milestone in inside {
            let fraction = FlybyPath.fraction(at: milestone.date, samples: samples)
            XCTAssertGreaterThan(fraction, 0)
            XCTAssertLessThan(fraction, 1)
            let back = FlybyPath.date(atFraction: fraction, samples: samples)
            XCTAssertEqual(back.timeIntervalSince(milestone.date), 0, accuracy: 1)
            let placed = try XCTUnwrap(FlybyPath.position(at: milestone.date, samples: samples))
            let range = (placed.x * placed.x + placed.y * placed.y + placed.z * placed.z).squareRoot()
            XCTAssertGreaterThan(range, document.radiusKm)
        }
    }

    func testClosestApproachIsTheMinimumOfTheTable() throws {
        let approach = try XCTUnwrap(FlybyPath.closestApproach(samples, radiusKm: document.radiusKm))
        let lowest = try XCTUnwrap(samples.min { $0.rangeKm < $1.rangeKm })
        let index = try XCTUnwrap(samples.firstIndex { $0.date == lowest.date })
        XCTAssertGreaterThan(index, 0)
        XCTAssertLessThan(index, samples.count - 1)
        XCTAssertLessThan(lowest.rangeKm, samples[index - 1].rangeKm)
        XCTAssertLessThan(lowest.rangeKm, samples[index + 1].rangeKm)
        XCTAssertLessThanOrEqual(approach.rangeKm, lowest.rangeKm)
        XCTAssertEqual(approach.altitudeKm, approach.rangeKm - document.radiusKm, accuracy: 0.0001)
        XCTAssertGreaterThan(approach.altitudeKm, 0)
        XCTAssertEqual(approach.date.timeIntervalSince(lowest.date), 0, accuracy: 60)
        let clock = ISO8601DateFormatter()
        clock.formatOptions = [.withInternetDateTime]
        let text = clock.string(from: approach.date)
        XCTAssertTrue(text.hasPrefix("2026-04-06T23:00:"))
    }

    func testApproachIntensityRisesTowardTheMinimum() throws {
        let approach = try XCTUnwrap(FlybyPath.closestApproach(samples, radiusKm: document.radiusKm))
        let early = FlybyPath.approachIntensity(at: samples[0].date, samples: samples, approach: approach)
        let later = FlybyPath.approachIntensity(at: samples[samples.count / 2].date, samples: samples, approach: approach)
        let near = FlybyPath.approachIntensity(at: approach.date, samples: samples, approach: approach)
        XCTAssertEqual(early, 0, accuracy: 0.02)
        XCTAssertGreaterThan(later, early)
        XCTAssertEqual(near, 1, accuracy: 0.05)
        XCTAssertFalse(FlybyPath.fadesInterface(at: samples[0].date, approach: approach.date))
        XCTAssertTrue(FlybyPath.fadesInterface(at: approach.date, approach: approach.date))
    }

    func testExhibitCardsQuoteTheTargetingPlan() throws {
        let url = try XCTUnwrap(Bundle(for: FlybyPathTests.self).url(forResource: "timeline", withExtension: "json"))
        let timeline = try Timeline(data: Data(contentsOf: url))
        XCTAssertEqual(ExhibitLibrary.cards.map(\.headline), [
            "Aristarchus Plateau", "Reiner Gamma", "Orientale Basin"
        ])
        XCTAssertEqual(
            ExhibitLibrary.cards[0].body,
            "Plateau known for its volcanic diversity and the bright Aristarchus crater, looking for color, albedo, and texture variations across the plateau and surrounding mare."
        )
        XCTAssertEqual(
            ExhibitLibrary.cards[1].body,
            "Set of bright lunar swirls near highland-mare boundary. Future CLPS landing site."
        )
        XCTAssertEqual(
            ExhibitLibrary.cards[2].body,
            "Youngest large basin on the Moon with dark impact melt interior, bright rings, and prominent ejecta with secondary crater chains."
        )
        for card in ExhibitLibrary.cards {
            let frame = try XCTUnwrap(ExhibitLibrary.frame(for: card, frames: timeline.frames))
            XCTAssertEqual(frame.targetID, card.targetID)
            XCTAssertFalse(frame.nasaID.isEmpty)
        }
    }

    func testGazetteerSitesSitOnTheUnitSphere() {
        XCTAssertEqual(LunarSites.marked.map(\.label), ["Aristarchus", "Reiner Gamma", "Orientale"])
        XCTAssertEqual(LunarSites.marked.map(\.feature), ["Aristarchus", "Reiner Gamma", "Mare Orientale"])
        XCTAssertEqual(LunarSites.marked[0].latitude, 23.73)
        XCTAssertEqual(LunarSites.marked[0].longitudeEast, -47.49)
        XCTAssertEqual(LunarSites.marked[1].latitude, 7.39)
        XCTAssertEqual(LunarSites.marked[1].longitudeEast, -58.96)
        XCTAssertEqual(LunarSites.marked[2].latitude, -19.87)
        XCTAssertEqual(LunarSites.marked[2].longitudeEast, -94.67)
        for site in LunarSites.marked {
            let point = MoonFrame.unit(latitude: site.latitude, longitudeEast: site.longitudeEast)
            let length = (point.x * point.x + point.y * point.y + point.z * point.z).squareRoot()
            XCTAssertEqual(length, 1, accuracy: 1e-9)
        }
        XCTAssertGreaterThan(MoonFrame.unit(latitude: 23.73, longitudeEast: -47.49).z, 0)
        XCTAssertLessThan(MoonFrame.unit(latitude: -19.87, longitudeEast: -94.67).z, 0)
    }

    func testSnapPullsASilentInstantOntoTheNearestRecording() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(900)
        let flyby = PathSpan(start: start, end: end)
        let gap = start.addingTimeInterval(860)
        let clip = PathSpan(start: start.addingTimeInterval(30), end: start.addingTimeInterval(400))
        let snapped = PathScrub.snap(gap, recordings: [clip], span: flyby)
        XCTAssertEqual(snapped, clip.end.addingTimeInterval(-0.05))
        XCTAssertNotEqual(snapped, end)
        XCTAssertNotEqual(snapped, gap)
        let inside = start.addingTimeInterval(54)
        XCTAssertEqual(PathScrub.snap(inside, recordings: [clip], span: flyby), inside)
        XCTAssertNil(PathScrub.snap(start, recordings: [], span: flyby))
    }

    /// The bright segment is only about 20pt wide. Horizontal travel uses the panel, not that arc.
    /// 22pt along the path's on-screen motion stays under two minutes, and does not land on the span end.
    func testTwentyTwoPointDragMovesUnderTwoMinutesAlongThePath() {
        let start = Date(timeIntervalSince1970: 1_000)
        let duration = 15.5 * 60.0
        let end = start.addingTimeInterval(duration)
        let span = PathSpan(start: start, end: end)
        let panel = 390.0
        let anchor = start.addingTimeInterval(duration * 0.30)
        let rightward = [
            PathScreenSample(date: start, x: 0, y: 100),
            PathScreenSample(date: end, x: 20, y: 100)
        ]
        let forward = PathScrub.drag(
            anchorDate: anchor,
            translationX: 22,
            panelWidth: panel,
            samples: rightward,
            span: span
        )
        let moved = forward?.date.timeIntervalSince(anchor) ?? 999
        XCTAssertEqual(PathScrub.forwardSign(at: anchor, samples: rightward), 1)
        XCTAssertGreaterThan(moved, 0)
        XCTAssertLessThan(moved, 120)
        XCTAssertEqual(moved, duration * 22 / panel, accuracy: 0.01)
        XCTAssertNotEqual(forward?.date, end)
        XCTAssertEqual(forward?.span, span)

        let across = PathScrub.drag(
            anchorDate: start,
            translationX: panel,
            panelWidth: panel,
            samples: rightward,
            span: span
        )
        XCTAssertEqual(across?.date, end)

        let leftward = [
            PathScreenSample(date: start, x: 20, y: 100),
            PathScreenSample(date: end, x: 0, y: 100)
        ]
        let along = PathScrub.drag(
            anchorDate: anchor,
            translationX: -22,
            panelWidth: panel,
            samples: leftward,
            span: span
        )
        let alongMoved = along?.date.timeIntervalSince(anchor) ?? -999
        XCTAssertEqual(PathScrub.forwardSign(at: anchor, samples: leftward), -1)
        XCTAssertGreaterThan(alongMoved, 0)
        XCTAssertLessThan(alongMoved, 120)
        XCTAssertNotEqual(along?.date, end)

        let against = PathScrub.drag(
            anchorDate: anchor,
            translationX: 22,
            panelWidth: panel,
            samples: leftward,
            span: span
        )
        let againstMoved = against?.date.timeIntervalSince(anchor) ?? 999
        XCTAssertLessThan(againstMoved, 0)
        XCTAssertGreaterThan(againstMoved, -120)
    }

    /// Horizontal travel stays on the span being scrubbed. A fold in the arc, or a drag toward the other span, does not leave it.
    func testHorizontalScrubClampsToTheCurrentSpan() {
        let start = Date(timeIntervalSince1970: 1_000)
        let duration = 900.0
        let end = start.addingTimeInterval(duration)
        let flyby = PathSpan(start: start, end: end)
        let folded = [
            PathScreenSample(date: start, x: 0, y: 0),
            PathScreenSample(date: start.addingTimeInterval(450), x: 100, y: 0),
            PathScreenSample(date: end, x: 6, y: 2)
        ]
        let foldedDrag = PathScrub.drag(
            anchorDate: start,
            translationX: 6,
            panelWidth: 390,
            samples: folded,
            span: flyby
        )
        let foldedDelta = foldedDrag?.date.timeIntervalSince(start) ?? 999
        XCTAssertEqual(foldedDrag?.span, flyby)
        XCTAssertGreaterThan(foldedDelta, 0)
        XCTAssertLessThan(foldedDelta, 90)
        XCTAssertNotEqual(foldedDrag?.date, end)

        let cab = PathSpan(start: start.addingTimeInterval(10_000), end: start.addingTimeInterval(10_500))
        let pastThePanel = PathScrub.drag(
            anchorDate: start,
            translationX: 5_000,
            panelWidth: 390,
            samples: folded,
            span: flyby
        )
        XCTAssertEqual(pastThePanel?.date, end)
        XCTAssertEqual(pastThePanel?.span, flyby)
        XCTAssertNotEqual(pastThePanel?.span, cab)

        let beforeTheStart = PathScrub.drag(
            anchorDate: start.addingTimeInterval(30),
            translationX: -5_000,
            panelWidth: 390,
            samples: folded,
            span: flyby
        )
        XCTAssertEqual(beforeTheStart?.date, start)
        XCTAssertEqual(beforeTheStart?.span, flyby)
    }

    /// Horizons quantity 15 at 2026-04-06 19:40 UT, CENTER=500@-1024, prints SunSub-LON 306.562535° and SunSub-LAT 1.028083°.
    func testSubSolarPointMatchesTheHorizonsQuery() throws {
        let document = try XCTUnwrap(SolarEphemeris.load())
        XCTAssertEqual(document.frame, "MOON_ME")
        XCTAssertTrue(document.query.contains("COMMAND=301"))
        XCTAssertTrue(document.query.contains("CENTER=500@-1024"))
        XCTAssertTrue(document.query.contains("QUANTITIES=15"))
        let row = try XCTUnwrap(document.samples.first { $0.t == "2026-04-06T19:40:00Z" })
        XCTAssertEqual(row.lonEast, 306.562535, accuracy: 0.000001)
        XCTAssertEqual(row.lat, 1.028083, accuracy: 0.000001)
        let samples = SolarEphemeris.samples(in: document)
        let date = Self.utc("2026-04-06T19:40:00Z")
        let direction = try XCTUnwrap(SolarEphemeris.direction(at: date, samples: samples))
        let expected = MoonFrame.unit(latitude: row.lat, longitudeEast: row.lonEast)
        XCTAssertEqual(direction.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(direction.y, expected.y, accuracy: 1e-9)
        XCTAssertEqual(direction.z, expected.z, accuracy: 1e-9)
    }

    /// A step from 350° to 10° crosses 0°, so the midpoint is 0° rather than 180°.
    func testSubSolarLongitudeTakesTheShortTurnAcrossZero() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [
            SunSample(date: start, longitudeEast: 350, latitude: 1),
            SunSample(date: start.addingTimeInterval(100), longitudeEast: 10, latitude: 3)
        ]
        XCTAssertEqual(SolarEphemeris.shortestTurn(from: 350, to: 10), 20, accuracy: 0.0001)
        XCTAssertEqual(SolarEphemeris.shortestTurn(from: 10, to: 350), -20, accuracy: 0.0001)
        let mid = SolarEphemeris.direction(at: start.addingTimeInterval(50), samples: samples)
        let expected = MoonFrame.unit(latitude: 2, longitudeEast: 0)
        XCTAssertEqual(mid?.x ?? -1, expected.x, accuracy: 1e-9)
        XCTAssertEqual(mid?.y ?? -1, expected.y, accuracy: 1e-9)
        XCTAssertEqual(mid?.z ?? -1, expected.z, accuracy: 1e-9)
    }
}