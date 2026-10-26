import UIKit
import XCTest
@testable import ArtemisIIWindow

final class HybridLayoutTests: XCTestCase {
    /// Open-fold width used by the old stage tests. Phone widths are 375, 402, and 440.
    private let widths: [CGFloat] = [375, 402, 440, 890]

    @MainActor
    func testCraterPixelsLandOnTheFittedStrip() throws {
        let aristarchus = (lon: -47.49, lat: 23.73)
        let reiner = (lon: -58.96, lat: 7.39)
        for width in widths {
            let size = TrackMapGeometry.fittedSize(width: width)
            XCTAssertEqual(size.width / size.height, TrackMapGeometry.pixelWidth / TrackMapGeometry.pixelHeight, accuracy: 0.0001)
            let aristarchusPoint = TrackMapGeometry.point(lon: aristarchus.lon, lat: aristarchus.lat, in: size)
            let reinerPoint = TrackMapGeometry.point(lon: reiner.lon, lat: reiner.lat, in: size)
            XCTAssertLessThan(
                reinerPoint.x,
                aristarchusPoint.x,
                "58.96° W is further west than 47.49° W, so Reiner Gamma is left of Aristarchus at \(width)"
            )
            XCTAssertLessThan(aristarchusPoint.y, reinerPoint.y)
        }
        try assertAristarchusIsABrightnessPeak()
    }

    /// Samples the flipped crater map at the Aristarchus point. The crater is a local bright patch.
    @MainActor
    private func assertAristarchusIsABrightnessPeak() throws {
        let loaded = TrackMapImage.load() ?? TrackMapImage.load(in: Bundle(for: HybridLayoutTests.self))
        let image = try XCTUnwrap(loaded?.cgImage)
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // The view mirrors x only (`scaleEffect(x: -1)`). This draw also flips y, and the
            // bitmap's first row is then the bottom of the file. Sampling view y directly read
            // file row 483: peak 169.7 against a ring of 165.4. The crater is file row 179.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(drew)
        let point = TrackMapGeometry.point(
            lon: -47.49,
            lat: 23.73,
            in: CGSize(width: CGFloat(width), height: CGFloat(height))
        )
        // West-left x maps back to the file by subtracting from the width. Y is inverted in this buffer.
        let centerX = width - Int(point.x.rounded())
        let centerY = height - 1 - Int(point.y.rounded())
        func luminance(_ x: Int, _ y: Int) -> Double {
            let clampedX = min(max(x, 0), width - 1)
            let clampedY = min(max(y, 0), height - 1)
            let index = clampedY * bytesPerRow + clampedX * 4
            return (Double(pixels[index]) + Double(pixels[index + 1]) + Double(pixels[index + 2])) / 3
        }
        var peak = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                peak = max(peak, luminance(centerX + dx, centerY + dy))
            }
        }
        var around = 0.0
        var count = 0
        for dy in -16...16 {
            for dx in -16...16 {
                let distance = dx * dx + dy * dy
                guard distance >= 8 * 8, distance <= 16 * 16 else { continue }
                around += luminance(centerX + dx, centerY + dy)
                count += 1
            }
        }
        let ring = around / Double(max(count, 1))
        XCTAssertGreaterThan(peak, ring + 40, "Aristarchus peak \(peak) vs surroundings \(ring)")
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
        XCTAssertEqual(RulerMetrics.y(fraction: 1, height: height), height - RulerMetrics.bottomInset(safeArea: 0))
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

        let stayed = model.utc
        model.showFlyby()
        XCTAssertEqual(model.range, .flyby)
        XCTAssertEqual(model.utc.timeIntervalSince(stayed), 0, accuracy: 0.01)
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
        for fraction in [0.0, 0.42, 1.0] {
            let tick = RulerMetrics.y(fraction: fraction, height: height)
            XCTAssertEqual(
                RulerLabelLayout.timeCenter(tick: tick, height: height),
                tick,
                accuracy: 0.01,
                "fraction \(fraction)"
            )
        }
        XCTAssertEqual(RulerMetrics.y(fraction: 0, height: height), RulerMetrics.topInset, accuracy: 0.01)
        XCTAssertEqual(RulerMetrics.y(fraction: 1, height: height), height - RulerMetrics.bottomInset(safeArea: 0), accuracy: 0.01)
        XCTAssertEqual(RulerLabelLayout.timeLine, 44, accuracy: 0.001)
        let safe: CGFloat = 34
        let approach = RulerMetrics.y(fraction: 1, height: height, safeArea: safe)
        XCTAssertEqual(approach, height - RulerMetrics.bottomInset(safeArea: safe), accuracy: 0.01)
        XCTAssertEqual(RulerLabelLayout.timeCenter(tick: approach, height: height, safeArea: safe), approach, accuracy: 0.01)
        let nameBottom = RulerLabelLayout.nameTop(center: approach) + RulerLabelLayout.nameLine
        XCTAssertLessThanOrEqual(nameBottom, height - safe)
    }

    func testSheetHeightGivesTheCaptionItsInsetBack() {
        let screen: CGFloat = 874
        let safe: CGFloat = 34
        let content = PanelMetrics.contentHeight(screenHeight: screen)
        XCTAssertEqual(content, 437, accuracy: 0.001)
        XCTAssertLessThanOrEqual(content, 460)
        XCTAssertGreaterThanOrEqual(content, 340)
        XCTAssertEqual(PanelMetrics.sheetHeight(screenHeight: screen, safeBottom: safe) - safe, content, accuracy: 0.001)
        XCTAssertEqual(PanelMetrics.contentHeight(screenHeight: 600), 340, accuracy: 0.001)
        XCTAssertEqual(PanelMetrics.sheetHeight(screenHeight: 1000, safeBottom: safe), 460 + safe, accuracy: 0.001)
        XCTAssertEqual(PanelMetrics.sheetHeight(screenHeight: screen, safeBottom: 0), content, accuracy: 0.001)
    }

    @MainActor
    func testShortPanelKeepsTheAristarchusNameClearOfTheNextLabel() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let height: CGFloat = 340
        let first = try XCTUnwrap(timeline.lines.first { $0.utc == RulerLabelMarks.aristarchus }?.date)
        let second = try XCTUnwrap(timeline.lines.first { $0.utc == RulerLabelMarks.aristarchusLine }?.date)
        let tickA = RulerMetrics.y(fraction: HybridClock.fraction(date: first, timeline: timeline), height: height)
        let tickB = RulerMetrics.y(fraction: HybridClock.fraction(date: second, timeline: timeline), height: height)
        let centerA = RulerLabelLayout.timeCenter(tick: tickA, height: height)
        let centerB = RulerLabelLayout.timeCenter(tick: tickB, height: height)
        let nameBottom = RulerLabelLayout.nameTop(center: centerA) + RulerLabelLayout.nameLine
        let nextTop = centerB - RulerLabelLayout.timeBand / 2
        XCTAssertLessThanOrEqual(nameBottom, nextTop)
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

    func testOrionReadoutKeepsTheFigureWithItsUnit() {
        let line = OrionReadout.unbroken("alt 13,864.77 km")
        XCTAssertFalse(line.contains(" "))
        XCTAssertTrue(line.contains("13,\u{2060}864.\u{2060}77"))
        XCTAssertTrue(line.hasSuffix("\u{00A0}km"))
        XCTAssertTrue(line.contains("\u{00A0}"))
    }

    @MainActor
    func testClosestApproachLandsOnTheNearestCabFrame() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let landing = try XCTUnwrap(ClosestApproachLanding.make(timeline: timeline))
        XCTAssertEqual(landing.frameID, "art002e041365")
        XCTAssertEqual(landing.window, .cab)
        XCTAssertEqual(landing.range, .cab)
        XCTAssertEqual(landing.trackID, "pcd2")
        let approachPoint = try XCTUnwrap(FlybyEphemeris.bundled.flatMap {
            FlybyPath.closestApproach($0.samples, radiusKm: $0.document.radiusKm)
        })
        let shown = ClosestApproachLanding.displayedInstant(approachPoint.date)
        XCTAssertEqual(ClockMath.utcText(approachPoint.date), "23:00:46 UTC")
        XCTAssertEqual(ClockMath.utcText(shown), "23:00:47 UTC")
        XCTAssertEqual(Int(approachPoint.altitudeKm.rounded()), 6545)
        XCTAssertEqual(approachPoint.radiusKm, 1737.4, accuracy: 0.001)
        XCTAssertEqual(
            landing.gap,
            "Closest approach: 23:00:47 UTC, 6,545 km above the Moon's 1,737.4 km mean radius (NASA/JPL Horizons). The nearest crew photo was taken 16 min 14 s earlier."
        )
        XCTAssertEqual(shown.timeIntervalSince(landing.date), 16 * 60 + 14, accuracy: 0.001)
        XCTAssertFalse(landing.gap.contains("this clock"))
        XCTAssertFalse(landing.gap.contains("Not moved"))
        let approach = HybridClock.approachDate(timeline: timeline)
        XCTAssertGreaterThan(approach.timeIntervalSince(landing.date), 60)

        model.showClosestApproach()
        XCTAssertEqual(model.utc.timeIntervalSince(landing.date), 0, accuracy: 0.01)
        XCTAssertEqual(model.window, .cab)
        XCTAssertEqual(model.range, .cab)
        XCTAssertEqual(model.approachGap, landing.gap)
        XCTAssertFalse(model.approachInformational)
        XCTAssertFalse(model.playing)
        XCTAssertGreaterThan(approach.timeIntervalSince(model.utc), 60)

        model.seek(to: timeline.window.start, markEnd: false)
        XCTAssertNil(model.approachGap)
    }

    @MainActor
    func testClosestApproachLandingDateIsTheCabFrame() throws {
        let model = PlaybackModel()
        let landing = try XCTUnwrap(model.closestApproach)
        XCTAssertEqual(landing.date, try ISO8601.parse("2026-04-06T22:44:33.000Z"))
        XCTAssertEqual(landing.frameID, "art002e041365")
    }

    @MainActor
    func testPlayAfterClosestApproachClearsTheGapAndRewinds() throws {
        let model = PlaybackModel()
        let cab = try XCTUnwrap(model.timeline?.cabRun)
        model.showClosestApproach()
        XCTAssertEqual(model.utc, try ISO8601.parse("2026-04-06T22:44:33.000Z"))
        XCTAssertNotNil(model.approachGap)
        XCTAssertFalse(model.approachInformational)
        model.play()
        XCTAssertNil(model.approachGap)
        XCTAssertFalse(model.approachInformational)
        XCTAssertEqual(model.utc, cab.start)
        XCTAssertEqual(ClockMath.utcText(model.utc), "22:36:03 UTC")
        XCTAssertTrue(model.playing)
    }

    @MainActor
    func testMissingApproachNoteExplainsTheTable() throws {
        let note = try XCTUnwrap(ClosestApproachLanding.missingNote())
        XCTAssertEqual(
            note,
            "Closest approach: 23:00:47 UTC, 6,545 km above the Moon's 1,737.4 km mean radius (NASA/JPL Horizons). No crew recording at that moment."
        )
        let timeline = try Self.bareTimeline(cab: false, utc: "2026-04-06T19:40:00.000Z", instrument: "nkd5015", frames: false)
        XCTAssertNil(ClosestApproachLanding.make(timeline: timeline))
        let model = PlaybackModel()
        model.adopt(timeline)
        XCTAssertNil(model.closestApproach)
        model.showClosestApproach()
        XCTAssertTrue(model.approachInformational)
        XCTAssertEqual(model.approachGap, note)
        XCTAssertEqual(model.utc, timeline.window.start)
    }

    func testClosestApproachTieBreakPrefersTheEarlierEqualDistance() {
        let approach = Date(timeIntervalSinceReferenceDate: 10_000)
        let before = approach.addingTimeInterval(-12)
        let after = approach.addingTimeInterval(12)
        let farther = approach.addingTimeInterval(40)
        XCTAssertTrue(ClosestApproachLanding.prefers(
            before, distance: 12, over: farther, currentDistance: 40, approach: approach
        ))
        XCTAssertFalse(ClosestApproachLanding.prefers(
            farther, distance: 40, over: before, currentDistance: 12, approach: approach
        ))
        XCTAssertTrue(ClosestApproachLanding.prefers(
            before, distance: 12, over: after, currentDistance: 12, approach: approach
        ))
        XCTAssertFalse(ClosestApproachLanding.prefers(
            after, distance: 12, over: before, currentDistance: 12, approach: approach
        ))
        let older = approach.addingTimeInterval(-9)
        let newer = approach.addingTimeInterval(-3)
        XCTAssertTrue(ClosestApproachLanding.prefers(
            older, distance: 9, over: newer, currentDistance: 9, approach: approach
        ))
        XCTAssertFalse(ClosestApproachLanding.prefers(
            newer, distance: 9, over: older, currentDistance: 9, approach: approach
        ))
    }

    @MainActor
    func testTrackFallbackMatchesTheSpan() throws {
        let flyby = try Self.bareTimeline(cab: false, utc: "2026-04-06T19:40:00.000Z", instrument: "nkd5015", frames: true)
        let flybyLanding = try XCTUnwrap(ClosestApproachLanding.make(timeline: flyby))
        XCTAssertEqual(flybyLanding.range, .flyby)
        XCTAssertEqual(flybyLanding.trackID, "pcd3")
        let cab = try Self.bareTimeline(cab: true, utc: "2026-04-06T22:40:00.000Z", instrument: "cab2", frames: true)
        let cabLanding = try XCTUnwrap(ClosestApproachLanding.make(timeline: cab))
        XCTAssertEqual(cabLanding.range, .cab)
        XCTAssertEqual(cabLanding.trackID, "pcd2")
    }

    @MainActor
    func testCaptionDropsALineTheSegmentDoesNotCover() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let landing = try XCTUnwrap(model.closestApproach)
        let parked = LyricFocus.focus(
            at: landing.date,
            track: landing.trackID,
            lines: timeline.lines,
            segments: timeline.segments
        )
        XCTAssertNil(parked.current)
        let line = try XCTUnwrap(timeline.lines.last { $0.track == "pcd2" })
        XCTAssertTrue(line.utc.hasPrefix("2026-04-06T19:48:28"))
        let spoken = LyricFocus.focus(
            at: line.date,
            track: line.track,
            lines: timeline.lines,
            segments: timeline.segments
        )
        XCTAssertEqual(spoken.current?.utc, line.utc)
        let stillFresh = LyricFocus.focus(
            at: line.date.addingTimeInterval(20),
            track: line.track,
            lines: timeline.lines,
            segments: timeline.segments
        )
        XCTAssertEqual(stillFresh.current?.utc, line.utc)
        let tooOld = LyricFocus.focus(
            at: line.date.addingTimeInterval(31),
            track: line.track,
            lines: timeline.lines,
            segments: timeline.segments
        )
        XCTAssertNil(tooOld.current)
        let heldAt = try ISO8601.parse("2026-04-06T19:36:00.000Z")
        let held = LyricFocus.focus(
            at: heldAt,
            track: "pcd2",
            lines: timeline.lines,
            segments: timeline.segments
        )
        let current = try XCTUnwrap(held.current)
        XCTAssertGreaterThan(heldAt.timeIntervalSince(current.date), LyricFocus.maximumCaptionAge)
        XCTAssertTrue(timeline.segments.contains { segment in
            segment.track == "pcd2"
                && current.date >= segment.start && current.date < segment.end
                && heldAt >= segment.start && heldAt < segment.end
        })
        XCTAssertNil(LyricFocus.focus(at: heldAt, track: "pcd2", lines: timeline.lines).current)
    }

    /// The capped card's scrollport is top padding plus a whole number of caption lines.
    func testCappedApproachViewportKeepsWholeLines() {
        let padding = ApproachLineGrid.textPadding
        let lineHeights: [CGFloat] = [18, 27.5, 44, 61]
        let rooms: [CGFloat] = [80, 96, 140, 200, 237.4, 360]
        for line in lineHeights {
            for room in rooms {
                let viewport = ApproachLineGrid.viewport(room: room, lineHeight: line)
                XCTAssertLessThanOrEqual(viewport, room + 0.001)
                XCTAssertGreaterThanOrEqual(viewport, 0)
                let inner = viewport - padding
                if room >= padding + line {
                    let lines = Int(floor((room - padding) / line))
                    XCTAssertGreaterThanOrEqual(inner, line - 0.001)
                    XCTAssertEqual(inner, CGFloat(lines) * line, accuracy: 0.01, "room \(room) line \(line)")
                } else {
                    XCTAssertLessThanOrEqual(viewport, padding + 0.001)
                }
            }
        }
        let cap: CGFloat = 248
        let room = cap - ApproachLineGrid.chevronRow
        let line: CGFloat = 33
        let viewport = ApproachLineGrid.viewport(room: room, lineHeight: line)
        let text = viewport - ApproachLineGrid.textPadding
        XCTAssertEqual(text, CGFloat(Int(floor((room - padding) / line))) * line, accuracy: 0.01)
        XCTAssertLessThanOrEqual(viewport + ApproachLineGrid.chevronRow, cap + 0.001)
        XCTAssertEqual(ApproachLineGrid.viewport(room: 180, lineHeight: 0), 180, accuracy: 0.001)
    }

    /// Open card on a 402×874 phone. The bottom stays one gap above the credit and the sheet
    /// at the default size, AX3, AX4, and AX5. The panel is the limit when it sits above the credit.
    func testOpenApproachCardCapClearsCreditAndPanel() throws {
        let screen: CGFloat = 874
        let safeTop: CGFloat = 62
        let revealed: CGFloat = 471
        let width: CGFloat = 362
        let categories: [(String, UIContentSizeCategory)] = [
            ("default", .large),
            ("AX3", .accessibilityExtraLarge),
            ("AX4", .accessibilityExtraExtraLarge),
            ("AX5", .accessibilityExtraExtraExtraLarge),
        ]
        var previousCredit: CGFloat = 0
        var creditHeights: [CGFloat] = []
        for (name, category) in categories {
            let traits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceIdiom: .phone),
                UITraitCollection(preferredContentSizeCategory: category),
            ])
            let creditHeight = CreditLine.height(fitting: width, compatibleWith: traits)
            XCTAssertGreaterThan(creditHeight, 8, name)
            XCTAssertGreaterThanOrEqual(creditHeight, previousCredit - 0.001, name)
            previousCredit = creditHeight
            creditHeights.append(creditHeight)

            let panelTop = screen - revealed
            let creditTop = panelTop - ClosedCaptionMetrics.openCreditLift - creditHeight
            XCTAssertLessThan(creditTop, panelTop, name)
            let cardHeight = ClosedCaptionMetrics.openApproachCardMaxHeight(
                screenHeight: screen,
                revealed: revealed,
                creditHeight: creditHeight,
                safeTop: safeTop
            )
            let limited = ClosedCaptionMetrics.openApproachCardMaxHeight(
                bottomLimit: min(creditTop, panelTop),
                safeTop: safeTop
            )
            XCTAssertEqual(cardHeight, limited, accuracy: 0.001, name)
            let top = ClosedCaptionMetrics.approachCardTopInset(safeTop: safeTop)
            let cardBottom = top + cardHeight
            let limit = min(creditTop, panelTop) - ClosedCaptionMetrics.approachCardGap
            XCTAssertGreaterThan(cardHeight, 0, name)
            XCTAssertEqual(cardBottom, limit, accuracy: 0.001, name)
            XCTAssertLessThanOrEqual(cardBottom, limit + 0.001, name)

            let room = max(0, cardHeight - ApproachLineGrid.chevronRow)
            let viewport = ApproachLineGrid.viewport(room: room, lineHeight: 33)
            let plate = ApproachLineGrid.plateHeight(offered: cardHeight, lineHeight: 33)
            XCTAssertEqual(plate, min(cardHeight, viewport + ApproachLineGrid.chevronRow), accuracy: 0.01, name)
            XCTAssertLessThanOrEqual(plate, cardHeight + 0.001, name)
            XCTAssertLessThan(cardHeight - plate, 34, name)
        }
        let defaultCredit = try XCTUnwrap(creditHeights.first)
        let largestCredit = try XCTUnwrap(creditHeights.last)
        XCTAssertGreaterThan(largestCredit, defaultCredit)

        let panelTop: CGFloat = 300
        let creditTop: CGFloat = 420
        let bottomLimit = min(creditTop, panelTop)
        XCTAssertEqual(bottomLimit, panelTop, accuracy: 0.001)
        let top = ClosedCaptionMetrics.approachCardTopInset(safeTop: safeTop)
        let panelLimited = ClosedCaptionMetrics.openApproachCardMaxHeight(
            bottomLimit: bottomLimit,
            safeTop: safeTop
        )
        let cardBottom = top + panelLimited
        XCTAssertEqual(
            panelLimited,
            panelTop - ClosedCaptionMetrics.approachCardGap - top,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(cardBottom, panelTop - ClosedCaptionMetrics.approachCardGap + 0.001)
        XCTAssertLessThan(cardBottom, creditTop - ClosedCaptionMetrics.approachCardGap)
    }

    private static func bareTimeline(cab: Bool, utc: String, instrument: String, frames: Bool) throws -> Timeline {
        let cabRun = cab
            ? #","cab_run": {"start": "2026-04-06T22:36:03.000Z", "end": "2026-04-06T22:44:33.000Z", "label": "Cab"}"#
            : ""
        let frame = frames
            ? #"""
            [{"utc": "\#(utc)", "nasa_id": "art002e000001", "instrument": "\#(instrument)", "camera_label": "Window", "file": "images/art002e000001.webp", "credit": "Credit: NASA/Artemis II Crew"}]
            """#
            : "[]"
        let json = """
        {"version": 1, "window": {"start": "2026-04-06T19:33:00.000Z", "end": "2026-04-06T19:48:30.000Z", "label": "Window"}, "attribution": {"credit": "Credit: NASA/Artemis II Crew", "endorsement": "Not a NASA product."}, "pointing": {"available": false, "provider": "none", "note": "none"}, "segments": [], "lines": [], "frames": \(frame), "targets": [], "crew": [], "licenses": [], "mission_start": {"utc": "2026-04-01T22:35:12Z", "source": "guide"}\(cabRun)}
        """
        return try Timeline(data: Data(json.utf8))
    }
}
