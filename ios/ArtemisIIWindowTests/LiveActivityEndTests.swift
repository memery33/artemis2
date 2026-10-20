import XCTest
@testable import ArtemisIIWindow

@MainActor
final class FakeFlybyActivities: FlybyActivityClient {
    var identifiersStore: [String]
    var ended: [String] = []

    init(identifiers: [String]) {
        identifiersStore = identifiers
    }

    func identifiers() -> [String] {
        identifiersStore
    }

    func end(identifiers: [String]) async {
        ended = identifiers
        let drop = Set(identifiers)
        identifiersStore.removeAll { drop.contains($0) }
    }

    var updatedPlaying: [Bool] = []

    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        updatedPlaying.append(state.playing)
        _ = staleDate
    }

    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        updatedPlaying.append(state.playing)
        _ = staleDate
    }
}

final class LiveActivityEndTests: XCTestCase {
    @MainActor
    func testEndAllImmediatelyEndsTheActivitiesFromThatTurn() async {
        let fake = FakeFlybyActivities(identifiers: ["left-over"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        await FlybyLiveActivity.endAllImmediately()
        XCTAssertEqual(fake.ended, ["left-over"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
    }

    /// An activity created after the dismissal was scheduled is not in the id snapshot, so the end cannot delete it.
    @MainActor
    func testEndSnapshotLeavesAnActivityRequestedAfterwards() async {
        let fake = FakeFlybyActivities(identifiers: ["stale"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let dismissal = FlybyLiveActivity.scheduleEndAllImmediately()
        fake.identifiersStore.append("fresh")
        await dismissal.value
        XCTAssertEqual(fake.ended, ["stale"])
        XCTAssertEqual(fake.identifiersStore, ["fresh"])
    }

    @MainActor
    func testLockScreenClockIsAbsoluteUTCAndHasNoBlankSeconds() throws {
        let utc = try ISO8601.parse("2026-04-06T19:38:45Z")
        let text = FlybyActivityCopy.lockScreenClock(utc)
        XCTAssertEqual(text, "at 19:38:45 UTC")
        XCTAssertFalse(text.contains("--"))
        let spanStart = try ISO8601.parse("2026-04-06T19:33:00Z")
        let spanEnd = try ISO8601.parse("2026-04-06T19:48:30Z")
        let timer = FlybyActivityCopy.elapsedTimer(now: Date(timeIntervalSince1970: 1_700_000_000), utc: utc, spanStart: spanStart, spanEnd: spanEnd)
        let state = FlybyActivityAttributes.ContentState(
            progress: 0.2,
            nextMilestone: "End of this span",
            speaker: "Wiseman",
            clock: text,
            playing: true,
            elapsedStart: timer.start,
            elapsedEnd: timer.end,
            elapsedText: timer.text
        )
        XCTAssertEqual(state.clock, "at 19:38:45 UTC")
        XCTAssertFalse(state.clock.contains("--"))
        XCTAssertFalse(state.elapsedText.contains("--"))
        XCTAssertEqual(state.elapsedText, "05:45 into the flyby")
    }

    /// Elapsed at a known mission time is `missionTime - span.start`, not the time of day.
    /// A midnight anchor plus `Text(timerInterval:showsHours:)` painted 19:33 as 19:38 and hid the seconds.
    func testElapsedAnchorMatchesTimeSinceSpanStart() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let spanStart = try ISO8601.parse("2026-04-06T19:33:00Z")
        let spanEnd = try ISO8601.parse("2026-04-06T19:48:30Z")
        let utc = try ISO8601.parse("2026-04-06T19:33:18Z")
        let early = FlybyActivityCopy.elapsedTimer(now: now, utc: utc, spanStart: spanStart, spanEnd: spanEnd)
        let elapsed = utc.timeIntervalSince(spanStart)
        XCTAssertEqual(elapsed, 18, accuracy: 0.001)
        XCTAssertEqual(now.timeIntervalSince(early.start), elapsed, accuracy: 0.001)
        XCTAssertEqual(early.end.timeIntervalSince(early.start), spanEnd.timeIntervalSince(spanStart), accuracy: 0.001)
        XCTAssertEqual(early.text, "00:18 into the flyby")
        XCTAssertEqual(FlybyActivityCopy.elapsedLabel(elapsed), early.text)
        // The retired midnight anchor was ~19h33m. This interval is 18 seconds, so a showsHours clock cannot recur.
        XCTAssertLessThan(now.timeIntervalSince(early.start), 60)
        XCTAssertGreaterThan(abs(now.timeIntervalSince(early.start) - (19 * 3600 + 33 * 60 + 18)), 60)

        let tail = try ISO8601.parse("2026-04-06T19:48:00Z")
        let late = FlybyActivityCopy.elapsedTimer(now: now, utc: tail, spanStart: spanStart, spanEnd: spanEnd)
        XCTAssertEqual(now.timeIntervalSince(late.start), tail.timeIntervalSince(spanStart), accuracy: 0.001)
        XCTAssertEqual(tail.timeIntervalSince(spanStart), 15 * 60, accuracy: 0.001)
        XCTAssertEqual(late.text, "15:00 into the flyby")
        XCTAssertEqual(late.end.timeIntervalSince(late.start), 15 * 60 + 30, accuracy: 0.001)
    }

    func testPausedMarkerIsAbsentWhilePlaying() {
        XCTAssertEqual(FlybyActivityAttributes.pausedLabel(playing: false), "Paused")
        XCTAssertNil(FlybyActivityAttributes.pausedLabel(playing: true))
    }

    /// The span end is April 2026. A stale date taken from that mission time is already past, so the activity is born stale.
    func testStaleDateIsInTheFutureRelativeToNow() throws {
        let now = Date()
        let utc = try ISO8601.parse("2026-04-06T19:40:00Z")
        let end = try ISO8601.parse("2026-04-06T19:48:30Z")
        XCTAssertLessThan(end.addingTimeInterval(60), now)

        let playing = FlybyActivityCopy.staleDate(now: now, playing: true, utc: utc, spanEnd: end, rate: 1)
        let remaining = end.timeIntervalSince(utc)
        XCTAssertEqual(playing.timeIntervalSince(now), remaining + 60, accuracy: 0.001)
        XCTAssertGreaterThan(playing, Date())

        let halfSpeed = FlybyActivityCopy.staleDate(now: now, playing: true, utc: utc, spanEnd: end, rate: 2)
        XCTAssertEqual(halfSpeed.timeIntervalSince(now), remaining / 2 + 60, accuracy: 0.001)
        XCTAssertGreaterThan(halfSpeed, Date())

        let atEnd = FlybyActivityCopy.staleDate(now: now, playing: true, utc: end, spanEnd: end, rate: 1)
        XCTAssertEqual(atEnd.timeIntervalSince(now), 60, accuracy: 0.001)
        XCTAssertGreaterThan(atEnd, Date())

        let paused = FlybyActivityCopy.staleDate(now: now, playing: false, utc: utc, spanEnd: end, rate: 0)
        XCTAssertEqual(paused.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
        XCTAssertGreaterThan(paused, Date())
    }

    @MainActor
    func testUnitTestHostStartsWithASilentActivityClient() {
        XCTAssertTrue(FlybyLiveActivity.client is SilentFlybyActivities)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// A playback run on the test host must not install the ActivityKit client.
    @MainActor
    func testPlaybackRunDoesNotConstructTheActivityClient() async {
        let model = PlaybackModel()
        model.play()
        model.pause(user: true)
        await FlybyLiveActivity.endAllImmediately()
        XCTAssertTrue(FlybyLiveActivity.client is SilentFlybyActivities)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// `-ui-tests` turns playback services off. Launch still ends a leftover, and it does not leave the ActivityKit client installed.
    @MainActor
    func testUITestLaunchEndsLeftoversWhenPlaybackServicesAreOff() async {
        let fake = FakeFlybyActivities(identifiers: ["left-over"])
        var built = 0
        let previousFactory = FlybyLiveActivity.systemClientFactory
        let previous = FlybyLiveActivity.install(SilentFlybyActivities())
        defer {
            FlybyLiveActivity.systemClientFactory = previousFactory
            FlybyLiveActivity.install(previous)
        }
        FlybyLiveActivity.systemClientFactory = {
            built += 1
            return fake
        }
        FlybyLiveActivity.endLeftoversAtLaunch(unitTestHost: false, allowsPlayback: false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["left-over"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        fake.identifiersStore = ["still-up"]
        FlybyLiveActivity.useSystemClient(unitTestHost: false, allowsPlayback: false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(built, 2)
        XCTAssertEqual(fake.ended, ["still-up"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertTrue(FlybyLiveActivity.client is SilentFlybyActivities)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// The shipping launch installs the client and ends leftovers. Playback services being on is not what gates the end.
    @MainActor
    func testShippingLaunchInstallsTheClientAndEndsLeftovers() async {
        let fake = FakeFlybyActivities(identifiers: ["left-over"])
        let previousFactory = FlybyLiveActivity.systemClientFactory
        let previous = FlybyLiveActivity.install(SilentFlybyActivities())
        defer {
            FlybyLiveActivity.systemClientFactory = previousFactory
            FlybyLiveActivity.install(previous)
        }
        FlybyLiveActivity.systemClientFactory = { fake }
        FlybyLiveActivity.endLeftoversAtLaunch(unitTestHost: false, allowsPlayback: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["left-over"])
        XCTAssertTrue(FlybyLiveActivity.client is FakeFlybyActivities)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// The unit-test host does not ask for an ActivityKit client, even when playback services are off.
    @MainActor
    func testUnitTestHostDoesNotBuildTheActivityClient() async {
        var built = false
        let previousFactory = FlybyLiveActivity.systemClientFactory
        defer { FlybyLiveActivity.systemClientFactory = previousFactory }
        FlybyLiveActivity.systemClientFactory = {
            built = true
            return FakeFlybyActivities(identifiers: [])
        }
        FlybyLiveActivity.useSystemClient(unitTestHost: true, allowsPlayback: false)
        FlybyLiveActivity.endLeftoversAtLaunch(unitTestHost: true, allowsPlayback: false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertFalse(built)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    func testEndActivitiesAndExitArgumentIsRecognized() {
        XCTAssertTrue(FlybyLiveActivity.shouldEndActivitiesAndExit(arguments: ["-ui-tests", "-endActivitiesAndExit"]))
        XCTAssertFalse(FlybyLiveActivity.shouldEndActivitiesAndExit(arguments: ["-ui-tests"]))
        XCTAssertFalse(FlybyLiveActivity.shouldEndActivitiesAndExit(arguments: ["-endActivitiesAndExit"]))
    }

    /// The exit relaunch ends through the ActivityKit client and does not leave that client installed.
    @MainActor
    func testEndActivitiesAndExitEndsThroughTheSystemClient() async {
        let fake = FakeFlybyActivities(identifiers: ["left-over"])
        var built = 0
        let previousFactory = FlybyLiveActivity.systemClientFactory
        let previous = FlybyLiveActivity.install(SilentFlybyActivities())
        defer {
            FlybyLiveActivity.systemClientFactory = previousFactory
            FlybyLiveActivity.install(previous)
        }
        FlybyLiveActivity.systemClientFactory = {
            built += 1
            return fake
        }
        await FlybyLiveActivity.endAllForExit(unitTestHost: false)
        XCTAssertEqual(built, 1)
        XCTAssertEqual(fake.ended, ["left-over"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertTrue(FlybyLiveActivity.client is SilentFlybyActivities)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// The unit-test host ends the injected client and does not construct ActivityKit.
    @MainActor
    func testEndActivitiesAndExitOnTheUnitTestHostDoesNotBuildActivityKit() async {
        let fake = FakeFlybyActivities(identifiers: ["left-over"])
        let previous = FlybyLiveActivity.install(fake)
        var built = false
        let previousFactory = FlybyLiveActivity.systemClientFactory
        defer {
            FlybyLiveActivity.systemClientFactory = previousFactory
            FlybyLiveActivity.install(previous)
        }
        FlybyLiveActivity.systemClientFactory = {
            built = true
            return FakeFlybyActivities(identifiers: [])
        }
        await FlybyLiveActivity.endAllForExit(unitTestHost: true)
        XCTAssertFalse(built)
        XCTAssertEqual(fake.ended, ["left-over"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// Launch ends leftovers through the injected client. The test host never constructs ActivityKit.
    @MainActor
    func testLaunchEndsLeftoversWithoutConstructingActivityKit() async {
        let fake = FakeFlybyActivities(identifiers: ["left-over"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        FlybyLiveActivity.endLeftoversAtLaunch()
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["left-over"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }

    /// A mid-span pause keeps the activity and marks it paused. The span end and a seek to that end dismiss it.
    @MainActor
    func testShippingPauseKeepsTheActivityAndSpanEndStopsIt() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        XCTAssertLessThan(model.utc, span.end)

        model.pause(user: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.updatedPlaying, [false])
        XCTAssertEqual(fake.identifiersStore, ["live"])

        model.utc = span.end
        model.pause(user: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
    }

    /// Pausing in the app and then locking the screen is the scene-phase background path.
    /// RootView applies `.background` through SceneActivity, which must keep the activity.
    @MainActor
    func testBackgroundingWhilePausedKeepsTheActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        XCTAssertLessThan(model.utc, span.end)

        model.pause(user: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertFalse(model.playing)

        SceneActivity.apply(.background, model: model)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])
        XCTAssertEqual(fake.updatedPlaying.last, false)
        XCTAssertFalse(model.ended)
        XCTAssertLessThan(model.utc, span.end)
    }

    /// A ruler drag inside the flyby, including a finger that reaches into the cab run,
    /// stays in the active span and does not end the Live Activity.
    @MainActor
    func testDraggingTheRulerKeepsTheLiveActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.playing = true
        let span = try XCTUnwrap(model.activeSpan)
        let timeline = try XCTUnwrap(model.timeline)
        let cab = try XCTUnwrap(timeline.cabRun)
        let inside = span.start.addingTimeInterval(120)

        model.beginScrub()
        model.scrubRuler(to: inside)
        XCTAssertEqual(model.utc.timeIntervalSince(inside), 0, accuracy: 0.01)
        model.scrubRuler(to: cab.start.addingTimeInterval(30))
        XCTAssertEqual(model.range, .flyby)
        XCTAssertEqual(model.window, .nikon)
        XCTAssertEqual(model.utc.timeIntervalSince(inside), 0, accuracy: 0.01)
        model.scrubRuler(to: span.end.addingTimeInterval(-1))
        XCTAssertEqual(
            model.utc.timeIntervalSince(span.end),
            -PlaybackModel.scrubEndMargin,
            accuracy: 0.05
        )
        model.scrubRuler(to: span.end)
        XCTAssertLessThan(model.utc, span.end)
        XCTAssertNotEqual(model.utc, span.end.addingTimeInterval(-0.05))
        model.endScrub(markEnd: false)
        model.advanceDisplayLinkForTest(to: 1)
        model.advanceDisplayLinkForTest(to: 2)
        await FlybyLiveActivity.finishQueuedWork()

        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])
        XCTAssertFalse(model.ended)
        XCTAssertTrue(model.playing)
        XCTAssertLessThan(model.utc, span.end)
    }

    /// A clip that finishes on the span end dismisses the activity.
    @MainActor
    func testClipFinishAtSpanEndEndsTheActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.setSceneActive(true)
        let span = try XCTUnwrap(model.activeSpan)
        let segment = try XCTUnwrap(model.timeline?.segments.first {
            $0.track == model.trackID && $0.start >= span.start && $0.start < span.end
        })
        model.playing = true
        model.finishCurrentClipForTest(
            file: segment.file,
            renderedSeconds: span.end.timeIntervalSince(segment.start) + 5
        )
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertTrue(model.ended)
    }

    /// The foreground clock reaching the span end dismisses the activity.
    @MainActor
    func testForegroundSpanEndEndsTheActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.setSceneActive(true)
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.utc = span.end
        model.advanceDisplayLinkForTest(to: 1)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertTrue(model.ended)
        XCTAssertEqual(model.utc, span.end)
    }

    /// Locking the phone before the span end keeps the Live Activity, even when
    /// this track has no file left to play. Only the clock reaching the end dismisses it.
    @MainActor
    func testBackgroundBeforeSpanEndKeepsTheActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        let parked = span.end.addingTimeInterval(-30)
        model.utc = parked
        model.setSceneActive(false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])
        XCTAssertFalse(model.ended)
        XCTAssertEqual(model.utc, parked)
        XCTAssertLessThan(model.utc, span.end)
    }

    /// After the last file, a locked phone follows wall time. The activity stays up
    /// until that clock reaches the span end, and it ends then — the same as an unlocked natural end.
    @MainActor
    func testLockedSilentTailEndsOnlyWhenWallTimeReachesSpanEnd() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        let parked = span.end.addingTimeInterval(-30)
        model.utc = parked
        model.setSceneActive(false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])
        XCTAssertFalse(model.ended)
        XCTAssertEqual(model.utc, parked)

        model.advanceSilentTailForTest(by: 10)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(parked), 10, accuracy: 0.05)
        XCTAssertLessThan(model.utc, span.end)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])

        model.advanceSilentTailForTest(by: 29)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(parked), 29, accuracy: 0.05)
        XCTAssertLessThan(model.utc, span.end)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertTrue(fake.ended.isEmpty)

        model.advanceSilentTailForTest(by: 30)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(span.end), 0, accuracy: 0.001)
        XCTAssertTrue(model.ended)
        XCTAssertFalse(model.playing)
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
    }

    /// A ruler dragged past the flyby end, released while playing, then locked,
    /// leaves the Live Activity up and the clock short of the span end.
    @MainActor
    func testScrubPastTheSpanEndKeepsTheLiveActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.playing = true
        let span = try XCTUnwrap(model.activeSpan)
        let margin = PlaybackModel.scrubEndMargin

        model.beginScrub()
        model.scrubRuler(to: span.end.addingTimeInterval(-0.25))
        model.scrubRuler(to: span.end.addingTimeInterval(45))
        model.endScrub(markEnd: false)
        model.advanceDisplayLinkForTest(to: 1)
        model.advanceDisplayLinkForTest(to: 2)
        await FlybyLiveActivity.finishQueuedWork()

        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertLessThanOrEqual(model.utc, span.end.addingTimeInterval(-margin + 1.1))
        XCTAssertGreaterThan(model.utc, span.end.addingTimeInterval(-margin - 0.05))
        XCTAssertLessThan(model.utc, span.end)
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])

        model.setSceneActive(false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])
        XCTAssertFalse(model.ended)
        XCTAssertLessThan(model.utc, span.end)
    }

    @MainActor
    func testSeekToTheSpanEndEndsTheActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        model.seek(to: span.end)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertFalse(FlybyLiveActivity.client is SystemFlybyActivities)
    }
}
