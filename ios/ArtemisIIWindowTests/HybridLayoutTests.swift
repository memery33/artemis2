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
