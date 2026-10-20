import XCTest
@testable import ArtemisIIWindow

final class HybridLayoutTests: XCTestCase {
    /// Open-fold width used by the old stage tests. Phone widths are 375, 402, and 440.
    private let widths: [CGFloat] = [375, 402, 440, 890]

    func testCraterPixelsLandOnTheFittedStrip() {
        let aristarchus = (lon: -47.49, lat: 23.73)
        let reiner = (lon: -58.96, lat: 7.39)
        for width in widths {
            let size = TrackMapGeometry.fittedSize(width: width)
            XCTAssertEqual(size.width / size.height, TrackMapGeometry.pixelWidth / TrackMapGeometry.pixelHeight, accuracy: 0.0001)
            let aristarchusPoint = TrackMapGeometry.point(lon: aristarchus.lon, lat: aristarchus.lat, in: size)
            let reinerPoint = TrackMapGeometry.point(lon: reiner.lon, lat: reiner.lat, in: size)
            assertMatchesFilePixel(aristarchusPoint, lon: aristarchus.lon, lat: aristarchus.lat, size: size)
            assertMatchesFilePixel(reinerPoint, lon: reiner.lon, lat: reiner.lat, size: size)
            XCTAssertLessThan(
                reinerPoint.x,
                aristarchusPoint.x,
                "58.96° W is further west than 47.49° W, so Reiner Gamma is left of Aristarchus at \(width)"
            )
            XCTAssertLessThan(aristarchusPoint.y, reinerPoint.y)
        }
    }

    @MainActor
    func testPlayableSpansTakeMostOfTheRulerAndShareOneInset() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let window = timeline.window
        let cab = try XCTUnwrap(timeline.cabRun)
        let observation = HybridClock.fraction(date: window.end, timeline: timeline)
            - HybridClock.fraction(date: window.start, timeline: timeline)
        let cabShare = HybridClock.fraction(date: cab.end, timeline: timeline)
            - HybridClock.fraction(date: cab.start, timeline: timeline)
        XCTAssertEqual(observation, HybridClock.observationWeight, accuracy: 0.0001)
        XCTAssertEqual(cabShare, HybridClock.cabWeight, accuracy: 0.0001)
        XCTAssertGreaterThan(observation + cabShare, 0.8)

        let sample = window.start.addingTimeInterval(100)
        let fraction = HybridClock.fraction(date: sample, timeline: timeline)
        let back = try XCTUnwrap(HybridClock.date(atFraction: fraction, timeline: timeline))
        XCTAssertEqual(back.timeIntervalSince(sample), 0, accuracy: 0.01)

        let height: CGFloat = 480
        XCTAssertEqual(RulerMetrics.y(fraction: 0, height: height), RulerMetrics.topInset)
        XCTAssertEqual(RulerMetrics.y(fraction: 1, height: height), height - RulerMetrics.bottomInset)
        let y = RulerMetrics.y(fraction: fraction, height: height)
        XCTAssertEqual(RulerMetrics.fraction(y: y, height: height), fraction, accuracy: 0.00001)
        let fromY = try XCTUnwrap(
            HybridClock.date(atFraction: RulerMetrics.fraction(y: y, height: height), timeline: timeline)
        )
        XCTAssertEqual(fromY.timeIntervalSince(sample), 0, accuracy: 0.01)
    }

    @MainActor
    func testClosestApproachIsOutsideEveryPlayableSpan() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let approach = HybridClock.approachDate(timeline: timeline)
        XCTAssertNil(HybridClock.playableApproach(timeline: timeline))
        XCTAssertGreaterThan(approach, timeline.window.end)
        let cab = try XCTUnwrap(timeline.cabRun)
        XCTAssertGreaterThan(approach, cab.end)
    }

    @MainActor
    func testOpeningLineComesFromTheWindow() throws {
        let model = PlaybackModel()
        let window = try XCTUnwrap(model.timeline?.window)
        XCTAssertEqual(HybridClock.openingLine(window: window), "19:33:00 UTC · 15 min 30 s")
    }

    @MainActor
    func testWindowTwoShowsGlushkoBeforeTheMoonFrame() throws {
        let model = PlaybackModel()
        let frames = try XCTUnwrap(model.timeline?.frames)
        let before = try ISO8601.parse("2026-04-06T19:33:10Z")
        XCTAssertEqual(HybridFrames.windowTwo(at: before, frames: frames)?.nasaID, "art002e009611")
        let during = try ISO8601.parse("2026-04-06T19:34:00Z")
        XCTAssertEqual(HybridFrames.windowTwo(at: during, frames: frames)?.nasaID, "art002e009611")
        let moon = try ISO8601.parse("2026-04-06T19:34:29.370Z")
        XCTAssertEqual(HybridFrames.windowTwo(at: moon, frames: frames)?.nasaID, "art002e009630")
    }

    @MainActor
    func testCraterOpticsUseTheFrameFocalLength() throws {
        let model = PlaybackModel()
        let frames = try XCTUnwrap(model.timeline?.frames)
        let aristarchus = try XCTUnwrap(frames.first { $0.nasaID == "art002e009806" })
        XCTAssertEqual(FrameOptics.line(aristarchus), "Window 2 · 400 mm")
        let reiner = try XCTUnwrap(frames.first { $0.nasaID == "art002e009943" })
        XCTAssertEqual(FrameOptics.line(reiner), "Window 2 · 400 mm")
        let glushko = try XCTUnwrap(frames.first { $0.nasaID == "art002e009611" })
        XCTAssertEqual(FrameOptics.line(glushko), "Window 2 · 270 mm")
    }

    @MainActor
    func testAristarchusLineReturnsToTheFlybyRecording() throws {
        let model = PlaybackModel()
        model.showCabRun()
        XCTAssertEqual(model.range, .cab)
        let line = try XCTUnwrap(model.timeline?.lines.first { $0.utc == "2026-04-06T19:36:05.938Z" })
        XCTAssertTrue(line.text.localizedCaseInsensitiveContains("Aristarchus"))
        model.showFlyby()
        model.seek(toLine: line)
        XCTAssertEqual(model.range, .flyby)
        XCTAssertEqual(model.window, .nikon)
        XCTAssertEqual(model.trackID, line.track)
        XCTAssertEqual(model.utc.timeIntervalSince(line.date), 0, accuracy: 0.01)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
    }

    func testMarkerLettersAndReadoutClearTheCraters() {
        XCTAssertEqual(TrackMapGeometry.markerLetter(for: "aristarchus"), "A")
        XCTAssertEqual(TrackMapGeometry.markerLetter(for: "reiner-gamma"), "R")
        XCTAssertNil(TrackMapGeometry.markerLetter(for: "orientale"))
        let aristarchus = (lon: -47.49, lat: 23.73)
        let reiner = (lon: -58.96, lat: 7.39)
        for width: CGFloat in [335, 362, 400, 520] {
            let size = TrackMapGeometry.fittedSize(width: width)
            let rect = TrackMapGeometry.fillRect(in: size)
            XCTAssertEqual(rect.width, size.width, accuracy: 0.5)
            XCTAssertEqual(rect.height, size.height, accuracy: 0.5)
            let markers = [
                TrackMapGeometry.point(lon: aristarchus.lon, lat: aristarchus.lat, in: rect),
                TrackMapGeometry.point(lon: reiner.lon, lat: reiner.lat, in: rect),
            ]
            let corner = TrackMapGeometry.readoutCorner(markers: markers, in: size)
            let box = corner.rect(in: size, box: CGSize(width: 124, height: 70), margin: 8)
            XCTAssertNotEqual(corner, .topTrailing, "Aristarchus sits in the top-right at \(width)")
            for marker in markers {
                XCTAssertGreaterThan(
                    TrackMapGeometry.distance(marker, from: box),
                    8,
                    "ORION box covers a marker at width \(width)"
                )
            }
        }
    }

    func testRulerTimeSitsOnItsTick() {
        let height: CGFloat = 700
        let tick = RulerMetrics.y(fraction: 0.42, height: height)
        XCTAssertEqual(RulerLabelLayout.timeCenter(tick: tick, height: height), tick, accuracy: 0.01)
        XCTAssertEqual(RulerLabelLayout.timeLine, 44, accuracy: 0.001)
    }

    func testDecodeCapIsTheScreenAndNotTheFile() {
        XCTAssertEqual(ScreenImage.maxPixel(size: CGSize(width: 402, height: 874), scale: 3), 2622, accuracy: 0.001)
        XCTAssertEqual(ScreenImage.maxPixel(size: CGSize(width: 440, height: 956), scale: 3), 2868, accuracy: 0.001)
        XCTAssertEqual(ScreenImage.maxPixel(size: CGSize(width: 2000, height: 2000), scale: 3), 3000, accuracy: 0.001)
        XCTAssertEqual(ScreenImage.maxPixel(size: .zero, scale: 1), 1600, accuracy: 0.001)
    }

    @MainActor
    func testLimbFramesCropTowardTheStoredFocus() throws {
        let model = PlaybackModel()
        let frames = try XCTUnwrap(model.timeline?.frames)
        for nasaID in ["art002e010041", "art002e009611"] {
            let frame = try XCTUnwrap(frames.first { $0.nasaID == nasaID })
            let x = try XCTUnwrap(frame.focusX)
            let y = try XCTUnwrap(frame.focusY)
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThanOrEqual(x, 1)
            XCTAssertGreaterThanOrEqual(y, 0)
            XCTAssertLessThanOrEqual(y, 1)
            let place = HybridFrames.placement(frame)
            XCTAssertTrue(place.focus)
            XCTAssertEqual(place.x, CGFloat(x), accuracy: 0.0001)
            XCTAssertEqual(place.y, CGFloat(y), accuracy: 0.0001)
            XCTAssertFalse(abs(Double(place.x) - 0.30) < 0.001 && abs(Double(place.y) - 0.50) < 0.001)
        }
        let glushko = try XCTUnwrap(frames.first { $0.nasaID == "art002e009611" })
        // The disk fills the left of the frame. The limb is near x 0.31 at the top
        // and x 0.45 a quarter of the way down. A focus in that band puts the edge
        // in the upper right of the portrait crop. The old centroid (0.19, 0.65) did not.
        let focusX = try XCTUnwrap(glushko.focusX)
        let focusY = try XCTUnwrap(glushko.focusY)
        XCTAssertGreaterThan(focusX, 0.28)
        XCTAssertLessThan(focusX, 0.36)
        XCTAssertGreaterThan(focusY, 0.30)
        XCTAssertLessThan(focusY, 0.50)
    }

    @MainActor
    func testLabeledRulerMarksIncludeTheReinerTick() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let approach = FlybyEphemeris.bundled.flatMap {
            FlybyPath.closestApproach($0.samples, radiusKm: $0.document.radiusKm)?.date
        }
        let dates = RulerLabelMarks.dates(timeline: timeline, approach: approach)
        let reiner = try XCTUnwrap(timeline.lines.first { $0.utc == RulerLabelMarks.reiner }?.date)
        XCTAssertTrue(dates.contains { abs($0.timeIntervalSince(reiner)) < 0.001 })
        let milestones = MilestoneList.derive(timeline).map(\.date)
        XCTAssertFalse(milestones.contains { abs($0.timeIntervalSince(reiner)) < 0.001 })
        XCTAssertGreaterThanOrEqual(dates.count, 3)
    }

    private func assertMatchesFilePixel(_ point: CGPoint, lon: Double, lat: Double, size: CGSize) {
        var east = lon.truncatingRemainder(dividingBy: 360)
        if east < 0 { east += 360 }
        let fileX = (340.0 - east) / (340.0 - 150.0) * 1400.0
        let fileY = (48.0 - lat) / 90.0 * 663.0
        let expectedX = (1400.0 - fileX) / 1400.0 * size.width
        let expectedY = fileY / 663.0 * size.height
        XCTAssertEqual(point.x, expectedX, accuracy: 0.01)
        XCTAssertEqual(point.y, expectedY, accuracy: 0.01)
    }
}
