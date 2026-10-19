import XCTest
@testable import ArtemisIIWindow

final class MilestonesTests: XCTestCase {
    private var timeline: Timeline!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: MilestonesTests.self).url(forResource: "timeline", withExtension: "json"))
        timeline = try Timeline(data: Data(contentsOf: url))
    }

    func testMilestonesComeFromTimelineFields() throws {
        let rows = MilestoneList.derive(timeline)
        XCTAssertEqual(rows.map(\.id), [
            "photo:art002e041321",
            "span:window.start",
            "audio:art002a000021",
            "quote:Aristarchus Plateau",
            "photo:art002e016183",
            "audio:art002a000031",
            "photo:art002e009611",
            "photo:art002e009806",
            "quote:Orientale Basin",
            "quote:Glushko Crater",
            "quote:Reiner Gamma",
            "photo:art002e009859",
            "quote:Ohm Crater",
            "audio:art002a000032",
            "audio:art002a000022",
            "photo:art002e009943",
            "audio:art002a000033",
            "photo:art002e010003",
            "quote:Vavilov Crater",
            "span:window.end",
            "photo:art002e041348",
            "span:cab_run.start",
            "audio:art002a000045",
            "span:cab_run.end",
        ])
        XCTAssertFalse(rows.contains {
            $0.label.localizedCaseInsensitiveContains("closest")
                || $0.source.localizedCaseInsensitiveContains("closest")
        })

        let quote = try XCTUnwrap(rows.first { $0.id == "quote:Aristarchus Plateau" })
        let line = try XCTUnwrap(timeline.lines.first { $0.utc == "2026-04-06T19:33:02.700Z" })
        XCTAssertEqual(quote.label, "\(line.speaker): \(line.text)")
        XCTAssertEqual(quote.utc, line.utc)
        XCTAssertEqual(quote.track, "pcd3")
        XCTAssertEqual(quote.source, "lines.utc, lines.speaker, lines.text, lines.track, lines.nasa_id, targets.name")

        let reiner = try XCTUnwrap(rows.first { $0.id == "quote:Reiner Gamma" })
        XCTAssertEqual(reiner.utc, "2026-04-06T19:37:21.559Z")
        XCTAssertTrue(reiner.label.hasPrefix("Wiseman: "))
        XCTAssertTrue(reiner.label.contains("Reiner Gamma"))

        let orientale = try XCTUnwrap(rows.first { $0.id == "photo:art002e009859" })
        let frame = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e009859" })
        XCTAssertEqual(orientale.label, "\(frame.targetID) · \(frame.nasaID)")
        XCTAssertEqual(orientale.utc, frame.utc)
        XCTAssertEqual(orientale.window, .nikon)
        XCTAssertEqual(orientale.source, "frames.utc, frames.nasa_id, frames.target_id, frames.instrument")

        let held = try XCTUnwrap(rows.first { $0.id == "photo:art002e041321" })
        XCTAssertEqual(held.utc, "2026-04-06T19:26:43.000Z")
        XCTAssertEqual(held.jumpUTC, timeline.window.startUTC)
        XCTAssertEqual(held.window, .cab)
        XCTAssertEqual(held.source, "frames.utc, frames.nasa_id, frames.look, frames.camera_label, window.start")

        let audio = try XCTUnwrap(rows.first { $0.id == "audio:art002a000021" })
        let segment = try XCTUnwrap(timeline.segments.first { $0.nasaID == "art002a000021" })
        XCTAssertEqual(audio.utc, segment.startUTC)
        XCTAssertEqual(audio.label, "\(segment.targetID) · \(segment.nasaID)")
        XCTAssertEqual(audio.track, segment.track)

        let windowStart = try XCTUnwrap(rows.first { $0.id == "span:window.start" })
        XCTAssertEqual(windowStart.label, timeline.window.label)
        XCTAssertEqual(windowStart.utc, timeline.window.startUTC)
        XCTAssertEqual(windowStart.source, "window.start, window.label")
    }

    func testSeekingLandsOnTheMilestoneOrThePlayableInstant() throws {
        let rows = MilestoneList.derive(timeline)
        let held = try XCTUnwrap(rows.first { $0.id == "photo:art002e041321" })
        let heldCue = MilestoneSeek.cue(
            for: held,
            timeline: timeline,
            range: .flyby,
            trackID: "pcd3",
            window: .nikon
        )
        XCTAssertEqual(heldCue.date, timeline.window.start)
        XCTAssertEqual(heldCue.range, .flyby)
        XCTAssertEqual(heldCue.window, .cab)
        XCTAssertEqual(heldCue.trackID, "pcd3")
        XCTAssertNotEqual(heldCue.date, held.date)

        let quote = try XCTUnwrap(rows.first { $0.id == "quote:Ohm Crater" })
        let quoteCue = MilestoneSeek.cue(
            for: quote,
            timeline: timeline,
            range: .flyby,
            trackID: "pcd3",
            window: .nikon
        )
        XCTAssertEqual(quoteCue.date, quote.date)
        XCTAssertEqual(quoteCue.trackID, "pcd2")
        XCTAssertEqual(quoteCue.window, .nikon)
        XCTAssertEqual(quote.utc, "2026-04-06T19:39:17.042Z")

        let cab = try XCTUnwrap(rows.first { $0.id == "span:cab_run.start" })
        let cabCue = MilestoneSeek.cue(
            for: cab,
            timeline: timeline,
            range: .flyby,
            trackID: "pcd3",
            window: .nikon
        )
        XCTAssertEqual(cabCue.range, .cab)
        XCTAssertEqual(cabCue.window, .cab)
        XCTAssertEqual(cabCue.date, timeline.cabRun?.start)
        XCTAssertEqual(cabCue.trackID, "pcd3")

        let reinerAudio = try XCTUnwrap(rows.first { $0.id == "audio:art002a000032" })
        let audioCue = MilestoneSeek.cue(
            for: reinerAudio,
            timeline: timeline,
            range: .cab,
            trackID: "pcd2",
            window: .cab
        )
        XCTAssertEqual(audioCue.range, .flyby)
        XCTAssertEqual(audioCue.trackID, "pcd2")
        XCTAssertEqual(audioCue.window, .cab)
        let segment = try XCTUnwrap(timeline.segments.first { $0.nasaID == "art002a000032" })
        XCTAssertEqual(audioCue.date, segment.start)
    }

    func testCoverageShowsAudioPhotosAndSilentGaps() throws {
        let flyby = MilestoneList.coverage(timeline: timeline, range: .flyby, track: "pcd3", window: .nikon)
        try assertIntervals(flyby.silent, [
            ("2026-04-06T19:33:00.000Z", "2026-04-06T19:33:01.758Z"),
            ("2026-04-06T19:42:08.999Z", "2026-04-06T19:42:17.718Z"),
            ("2026-04-06T19:47:40.000Z", "2026-04-06T19:48:30.000Z"),
        ])
        try assertIntervals(flyby.audio, [
            ("2026-04-06T19:33:01.758Z", "2026-04-06T19:42:08.999Z"),
            ("2026-04-06T19:42:17.718Z", "2026-04-06T19:47:40.000Z"),
        ])
        let aristarchus = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e009806" })
        let cabin = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e016183" })
        let cab = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e041322" })
        XCTAssertTrue(flyby.photos.contains(aristarchus.date))
        XCTAssertTrue(flyby.photos.contains(cabin.date))
        XCTAssertFalse(flyby.photos.contains(cab.date))

        let window3 = MilestoneList.coverage(timeline: timeline, range: .flyby, track: "pcd3", window: .cab)
        let stale = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e041321" })
        XCTAssertTrue(window3.photos.contains(cab.date))
        XCTAssertFalse(window3.photos.contains(stale.date))
        XCTAssertFalse(window3.photos.contains(aristarchus.date))
    }

    func testDarkFrameNamesTheBrightPatchAndItsAge() throws {
        let frame = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e041321" })
        XCTAssertEqual(frame.look, "dark")
        XCTAssertTrue(frame.exposureNote.localizedCaseInsensitiveContains("bright patch"))
        let appearance = FrameSelection.appearance(frame)
        XCTAssertTrue(appearance.contains("small bright patch"))
        XCTAssertTrue(appearance.contains("Mostly dark"))
        XCTAssertFalse(appearance.localizedCaseInsensitiveContains("nearly black"))

        let now = try ISO8601.parse("2026-04-06T19:34:05Z")
        XCTAssertEqual(
            FrameSelection.clockOffset(now: now, taken: frame.date),
            "Photo taken 7 min 22 s before this clock. Not moved to match it."
        )
        let fresh = frame.date.addingTimeInterval(1)
        XCTAssertNil(FrameSelection.clockOffset(now: fresh, taken: frame.date))

        let surface = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e041348" })
        XCTAssertFalse(FrameSelection.appearance(surface).localizedCaseInsensitiveContains("bright patch"))
        XCTAssertTrue(FrameSelection.appearance(surface).contains("Shown as photographed"))
    }

    func testMomentsUseFriendlySourceLabels() throws {
        let rows = MilestoneList.derive(timeline)
        let audio = try XCTUnwrap(rows.first { $0.id == "audio:art002a000021" })
        XCTAssertEqual(
            MilestoneSource.display(audio.source),
            "Audio start, NASA ID, Audio track, Target"
        )
        for row in rows {
            let friendly = MilestoneSource.display(row.source)
            XCTAssertFalse(friendly.isEmpty)
            XCTAssertFalse(friendly.contains("."))
            XCTAssertFalse(friendly.contains("segments.start"))
            XCTAssertFalse(friendly.contains("frames.utc"))
        }
    }

    func testVoiceOverAdjustSkipsWithoutScrubbing() {
        XCTAssertEqual(ClockNudge.interval, 15)
        XCTAssertEqual(ClockNudge.forward.seconds, ClockNudge.interval)
        XCTAssertEqual(ClockNudge.back.seconds, -ClockNudge.interval)
        XCTAssertEqual(PlaybackModel.skipInterval, ClockNudge.interval)
        XCTAssertFalse(ClockNudge.forward.scrubs)
        XCTAssertFalse(ClockNudge.back.scrubs)
    }

    @MainActor
    func testAccessibilityAdjustSkipsAboutFifteenSecondsWithoutScrubbing() {
        let model = PlaybackModel()
        XCTAssertNil(model.loadError)
        XCTAssertNotNil(model.activeSpan)
        XCTAssertFalse(model.scrubbing)
        let start = model.utc

        model.accessibilityAdjust(.increment)
        XCTAssertEqual(model.utc.timeIntervalSince(start), ClockNudge.interval, accuracy: 0.5)
        XCTAssertFalse(model.scrubbing)

        let forwarded = model.utc
        model.accessibilityAdjust(.decrement)
        XCTAssertEqual(model.utc.timeIntervalSince(forwarded), -ClockNudge.interval, accuracy: 0.5)
        XCTAssertFalse(model.scrubbing)
    }

    @MainActor
    func testDiveOpensTheWindowAndSurfaceReturnsToTheMoon() throws {
        let model = PlaybackModel()
        XCTAssertNil(model.loadError)
        XCTAssertFalse(model.immersed)
        model.dive()
        XCTAssertTrue(model.immersed)
        model.surface()
        XCTAssertFalse(model.immersed)
        let timeline = try XCTUnwrap(model.timeline)
        let pin = try XCTUnwrap(MilestoneList.derive(timeline).first { $0.id == "span:window.start" })
        model.dive(to: pin)
        XCTAssertTrue(model.immersed)
        XCTAssertEqual(model.utc.timeIntervalSince(pin.date), 0, accuracy: 1)
    }

    func testLyricsShowTheWholeLineAndItsNeighbors() throws {
        let track = "pcd3"
        let rows = timeline.lines.filter { $0.track == track }.sorted { $0.date < $1.date }
        let current = try XCTUnwrap(rows.dropFirst().first)
        let focus = LyricFocus.focus(at: current.date.addingTimeInterval(0.5), track: track, lines: timeline.lines)
        XCTAssertEqual(focus.current?.text, current.text)
        XCTAssertEqual(focus.current?.speaker, current.speaker)
        XCTAssertEqual(focus.previous?.date, rows[rows.firstIndex(of: current)! - 1].date)
        XCTAssertGreaterThan(focus.upcoming?.date ?? .distantPast, current.date)
        XCTAssertEqual(focus.current?.text.count, current.text.count)
    }

    @MainActor
    func testFollowCrewSelectsThatTrack() throws {
        let model = PlaybackModel()
        let member = try XCTUnwrap(model.timeline?.crew.first { $0.id == "Hansen" })
        model.follow(member)
        XCTAssertEqual(model.crewID, "Hansen")
        XCTAssertEqual(model.trackID, member.track)
    }

    func testLiveActivityCopyUsesTheSpanAndTheNextMilestone() throws {
        XCTAssertEqual(FlybyActivityCopy.progress(elapsed: 0, duration: 100), 0)
        XCTAssertEqual(FlybyActivityCopy.progress(elapsed: 25, duration: 100), 0.25)
        XCTAssertEqual(FlybyActivityCopy.progress(elapsed: 140, duration: 100), 1)
        XCTAssertEqual(FlybyActivityCopy.progress(elapsed: 10, duration: 0), 0)
        let rows = MilestoneList.derive(timeline)
        let first = rows[0].date
        XCTAssertEqual(FlybyActivityCopy.nextLabel(after: first.addingTimeInterval(-1), milestones: rows), rows[0].label)
        let last = try XCTUnwrap(rows.last)
        XCTAssertEqual(FlybyActivityCopy.nextLabel(after: last.date, milestones: rows), "End of this span")
        let clock = FlybyActivityCopy.clock(try ISO8601.parse("2026-04-06T19:33:01Z"))
        XCTAssertEqual(clock, "19:33:01")
    }

    @MainActor
    func testSeekingToTheSpanEndShowsTheEndCard() throws {
        let model = PlaybackModel()
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.seek(to: span.end.addingTimeInterval(30))
        XCTAssertTrue(model.ended)
        XCTAssertEqual(model.utc, span.end)
        XCTAssertFalse(model.playing)

        model.seek(to: span.start)
        XCTAssertFalse(model.ended)
        XCTAssertEqual(model.utc, span.start)
    }

    @MainActor
    func testPathScrubKeepsPlayingAndDoesNotJumpToTheSpanEnd() throws {
        let model = PlaybackModel()
        let timeline = try XCTUnwrap(model.timeline)
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        let target = span.start.addingTimeInterval(120)
        model.beginPathScrub()
        model.scrubPath(to: target)
        XCTAssertTrue(model.scrubbing)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertEqual(model.utc.timeIntervalSince(target), 0, accuracy: 0.5)
        XCTAssertLessThan(model.utc, span.end.addingTimeInterval(-60))

        let cab = try XCTUnwrap(timeline.cabRun)
        let cabTime = cab.start.addingTimeInterval(45)
        model.scrubPath(to: cabTime)
        XCTAssertEqual(model.range, .cab)
        XCTAssertEqual(model.utc.timeIntervalSince(cabTime), 0, accuracy: 0.5)
        XCTAssertLessThan(model.utc, cab.end)
        XCTAssertTrue(model.playing)
        XCTAssertNotEqual(model.utc, span.end)
        XCTAssertNotEqual(model.utc, cab.end)

        model.scrubPath(to: span.start.addingTimeInterval(-3600))
        XCTAssertEqual(model.utc.timeIntervalSince(cabTime), 0, accuracy: 0.5)

        model.endPathScrub()
        XCTAssertFalse(model.scrubbing)
        XCTAssertNotNil(model.segment(at: model.utc))
        XCTAssertGreaterThan(model.utc, cab.start)
        XCTAssertLessThan(model.utc, cab.end)
        XCTAssertNotEqual(model.utc, cab.end)
        XCTAssertNotEqual(model.utc, span.end)
        if !model.engineFailed {
            XCTAssertTrue(model.playing)
        }
        XCTAssertFalse(model.ended)
    }

    @MainActor
    func testReleasingAPathDragAtTheSpanEndShowsTheEndCard() throws {
        let model = PlaybackModel()
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.beginPathScrub()
        model.scrubPath(to: span.end)
        XCTAssertEqual(model.utc, span.end)
        XCTAssertFalse(model.ended)
        model.endPathScrub()
        XCTAssertFalse(model.scrubbing)
        XCTAssertTrue(model.ended)
        XCTAssertEqual(model.utc, span.end)
        XCTAssertFalse(model.playing)

        XCTAssertTrue(PlaybackModel.opensAtSpanEnd(["-seekToEnd"]))
        XCTAssertFalse(PlaybackModel.opensAtSpanEnd([]))
        XCTAssertFalse(RuntimeHost.allowsPlaybackServices(arguments: ["-XCTest"], unitTestHost: true))
        XCTAssertFalse(RuntimeHost.allowsPlaybackServices(arguments: ["-ui-tests", "-seekToEnd"], unitTestHost: false))
        XCTAssertTrue(RuntimeHost.allowsPlaybackServices(arguments: ["-ui-tests", "-allow-playback-session"], unitTestHost: true))
        XCTAssertTrue(RuntimeHost.allowsPlaybackServices(arguments: [], unitTestHost: false))
    }

    @MainActor
    func testDiveOpensAtTheSelectedMoment() throws {
        let model = PlaybackModel()
        let span = try XCTUnwrap(model.activeSpan)
        let moment = span.start.addingTimeInterval(90)
        model.seek(to: moment)
        model.playing = true
        model.dive()
        XCTAssertTrue(model.immersed)
        XCTAssertFalse(model.ended)
        XCTAssertEqual(model.utc.timeIntervalSince(moment), 0, accuracy: 0.5)
        XCTAssertLessThan(model.utc, span.end)

        let pin = try XCTUnwrap(MilestoneList.derive(try XCTUnwrap(model.timeline)).first { $0.id == "span:window.start" })
        model.dive(to: pin)
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 0, accuracy: 0.5)
        XCTAssertFalse(model.ended)
        XCTAssertNotEqual(model.utc, span.end)
    }

    func testPhotoAccessLabelOmitsTheLiveGap() throws {
        let frame = try XCTUnwrap(timeline.frames.first { $0.nasaID == "art002e041322" })
        let spoken = FrameSelection.photoAccessLabel(frame)
        XCTAssertTrue(spoken.contains("art002e041322"))
        XCTAssertTrue(spoken.contains("19:34:44"))
        XCTAssertFalse(spoken.contains("before this clock"))
        XCTAssertFalse(spoken.contains("after this clock"))
        let now = try ISO8601.parse("2026-04-06T19:34:05Z")
        let visible = FrameSelection.outsideSpanNotice(frame: frame, now: now)
        let quiet = FrameSelection.outsideSpanNotice(frame: frame, now: now, includeAge: false)
        XCTAssertTrue(visible.contains("after this clock"))
        XCTAssertFalse(quiet.contains("after this clock"))
        XCTAssertTrue(quiet.hasPrefix("Outside this span."))
    }

    private func assertIntervals(_ rows: [SpanCoverage.Interval], _ expected: [(String, String)]) throws {
        XCTAssertEqual(rows.count, expected.count)
        for (row, pair) in zip(rows, expected) {
            XCTAssertEqual(row.start, try ISO8601.parse(pair.0))
            XCTAssertEqual(row.end, try ISO8601.parse(pair.1))
        }
    }
}
