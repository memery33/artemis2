import UIKit
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
        XCTAssertEqual(document.frame, "MEAN_ME")
        XCTAssertEqual(document.radiusKm, 1737.4)
        XCTAssertGreaterThan(samples.count, 400)
        XCTAssertEqual(document.samples.first?.t, "2026-04-06T18:00:00Z")
        XCTAssertEqual(document.samples.last?.t, "2026-04-07T02:00:00Z")
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

    func testParallaxStaysInsideItsLimits() {
        let still = ParallaxShift.shift(pitch: 0.4, roll: -0.4, enabled: false)
        XCTAssertEqual(still, .zero)
        let hard = ParallaxShift.shift(pitch: 4, roll: -4, enabled: true)
        XCTAssertEqual(hard.photoX, -ParallaxShift.photoLimit)
        XCTAssertEqual(hard.photoY, ParallaxShift.photoLimit)
        XCTAssertEqual(hard.frameX, -ParallaxShift.frameLimit)
        XCTAssertEqual(hard.frameY, ParallaxShift.frameLimit)
        let gentle = ParallaxShift.shift(pitch: 0.1, roll: -0.1, enabled: true)
        XCTAssertLessThan(abs(gentle.photoX), ParallaxShift.photoLimit)
        XCTAssertLessThan(abs(gentle.frameY), ParallaxShift.frameLimit)
        XCTAssertGreaterThan(abs(gentle.frameX), 0)
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

    func testLROColorMapLoadsFromTheBundle() throws {
        let url = try XCTUnwrap(MoonMap.resourceURL())
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 100_000)
        let image = try XCTUnwrap(MoonMap.image())
        let pixels = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(pixels.width, 2048)
        XCTAssertEqual(pixels.height, 1024)
    }

    func testSlightDragStaysOnTheCurrentBrightSegment() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(900)
        let cabStart = start.addingTimeInterval(10_000)
        let cabEnd = cabStart.addingTimeInterval(500)
        let flyby = PathSpan(start: start, end: end)
        let cab = PathSpan(start: cabStart, end: cabEnd)
        let flybySamples = [
            PathScreenSample(date: start, x: 0, y: 0),
            PathScreenSample(date: end, x: 200, y: 0)
        ]
        let cabSamples = [
            PathScreenSample(date: cabStart, x: 0, y: 400),
            PathScreenSample(date: cabEnd, x: 20, y: 400)
        ]
        let slight = PathScrub.scrub(
            x: 4,
            y: 2,
            current: (flyby, flybySamples),
            others: [(cab, cabSamples)]
        )
        XCTAssertEqual(slight?.span, flyby)
        XCTAssertEqual(slight?.date.timeIntervalSince(start) ?? -1, 18, accuracy: 2)
        XCTAssertNotEqual(slight?.date, cabEnd)

        let reached = PathScrub.scrub(
            x: 10,
            y: 400,
            current: (flyby, flybySamples),
            others: [(cab, cabSamples)]
        )
        XCTAssertEqual(reached?.span, cab)
        XCTAssertEqual(reached?.date.timeIntervalSince(cabStart) ?? -1, 250, accuracy: 2)
        XCTAssertNotEqual(reached?.date, cabEnd)

        let clip = PathSpan(start: start.addingTimeInterval(30), end: start.addingTimeInterval(400))
        let snapped = PathScrub.snap(start, recordings: [clip], span: flyby)
        XCTAssertEqual(snapped, clip.start)
        XCTAssertNotEqual(snapped, end)
        XCTAssertNil(PathScrub.snap(start, recordings: [], span: flyby))
    }
}