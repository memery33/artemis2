import UIKit
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
    var lastState: FlybyActivityAttributes.ContentState?

    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        lastState = state
        updatedPlaying.append(state.playing)
        _ = staleDate
    }

    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        lastState = state
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

    /// The UTC line and the elapsed line are built from one mission instant, then stored on one ContentState.
    @MainActor
    func testLockScreenClockAndElapsedComeFromOneInstant() throws {
        let spanStart = try ISO8601.parse("2026-04-06T19:33:00Z")
        let utc = try ISO8601.parse("2026-04-06T19:33:06Z")
        let reading = FlybyActivityCopy.reading(utc: utc, spanStart: spanStart, phrase: "into the flyby")
        let elapsed = utc.timeIntervalSince(spanStart)
        XCTAssertEqual(elapsed, 6, accuracy: 0.001)
        XCTAssertEqual(reading.clock, "at 19:33:06 UTC")
        XCTAssertEqual(reading.elapsedText, FlybyActivityCopy.elapsedLabel(elapsed, phrase: "into the flyby"))
        XCTAssertEqual(reading.elapsedText, "0:06 into the flyby")
        XCTAssertFalse(reading.clock.contains("--"))
        XCTAssertFalse(reading.elapsedText.contains("--"))

        let playing = FlybyActivityAttributes.ContentState(
            progress: elapsed / (15 * 60 + 30),
            nextMilestone: "End of this span",
            speaker: "Wiseman",
            clock: reading.clock,
            playing: true,
            elapsedText: reading.elapsedText
        )
        let paused = FlybyActivityAttributes.ContentState(
            progress: playing.progress,
            nextMilestone: playing.nextMilestone,
            speaker: playing.speaker,
            clock: reading.clock,
            playing: false,
            elapsedText: reading.elapsedText
        )
        XCTAssertEqual(playing.clock, paused.clock)
        XCTAssertEqual(playing.elapsedText, paused.elapsedText)
        XCTAssertEqual(playing.elapsedText, "0:06 into the flyby")

        let later = try ISO8601.parse("2026-04-06T19:38:45Z")
        let five = FlybyActivityCopy.reading(utc: later, spanStart: spanStart, phrase: "into the flyby")
        XCTAssertEqual(five.clock, "at 19:38:45 UTC")
        XCTAssertEqual(five.elapsedText, "5:45 into the flyby")
        XCTAssertEqual(FlybyActivityCopy.elapsedLabel(54, phrase: "into the flyby"), "0:54 into the flyby")

        let tail = try ISO8601.parse("2026-04-06T19:48:00Z")
        let fifteen = FlybyActivityCopy.reading(utc: tail, spanStart: spanStart, phrase: "into the flyby")
        XCTAssertEqual(tail.timeIntervalSince(spanStart), 15 * 60, accuracy: 0.001)
        XCTAssertEqual(fifteen.clock, "at 19:48:00 UTC")
        XCTAssertEqual(fifteen.elapsedText, "15:00 into the flyby")

        let cab = FlybyActivityCopy.reading(utc: later, spanStart: spanStart, phrase: FlybyActivityCopy.elapsedPhrase(range: .cab))
        XCTAssertEqual(cab.clock, five.clock)
        XCTAssertEqual(cab.elapsedText, "5:45 into the cab run")

        let encoded = try JSONEncoder().encode(playing)
        let decoded = try JSONDecoder().decode(FlybyActivityAttributes.ContentState.self, from: encoded)
        XCTAssertEqual(decoded.clock, playing.clock)
        XCTAssertEqual(decoded.elapsedText, playing.elapsedText)
    }

    /// An activity pushed by an older build has no elapsed field. It must still decode.
    func testStaleActivityDecodesWithoutElapsedText() throws {
        let json = """
        {"progress":0.1,"nextMilestone":"End of this span","speaker":"Wiseman","clock":"at 19:33:02 UTC","playing":true,"clockStart":0,"clockEnd":1,"elapsedStart":0,"elapsedEnd":1}
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(FlybyActivityAttributes.ContentState.self, from: json)
        XCTAssertEqual(state.clock, "at 19:33:02 UTC")
        XCTAssertEqual(state.speaker, "Wiseman")
        XCTAssertTrue(state.playing)
        XCTAssertEqual(state.elapsedText, "")
        XCTAssertEqual(state.progress, 0.1, accuracy: 0.0001)
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

    /// A ruler drag stays in the flyby. A finger that reaches the cab run, or any date past
    /// the span end, clamps to end − 8 s. The Live Activity stays up.
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
        XCTAssertEqual(
            model.utc.timeIntervalSince(span.end.addingTimeInterval(-PlaybackModel.scrubEndMargin)),
            0,
            accuracy: 0.01
        )
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
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        model.wallNow = { origin }
        model.setSceneActive(false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])
        XCTAssertFalse(model.ended)
        XCTAssertEqual(model.utc, parked)

        model.wallNow = { origin.addingTimeInterval(10) }
        model.backgroundTick()
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(parked), 10, accuracy: 0.05)
        XCTAssertLessThan(model.utc, span.end)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])

        model.wallNow = { origin.addingTimeInterval(29) }
        model.backgroundTick()
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(parked), 29, accuracy: 0.05)
        XCTAssertLessThan(model.utc, span.end)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertTrue(fake.ended.isEmpty)

        model.setSceneActive(true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(parked), 29, accuracy: 0.05)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(fake.identifiersStore, ["live"])

        model.wallNow = { origin.addingTimeInterval(29) }
        model.setSceneActive(false)
        model.wallNow = { origin.addingTimeInterval(30) }
        model.backgroundTick()
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(model.utc.timeIntervalSince(span.end), 0, accuracy: 0.001)
        XCTAssertTrue(model.ended)
        XCTAssertFalse(model.playing)
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
    }

    /// Unlocking after the wall clock has already passed the span end dismisses the activity.
    /// The catch-up is the scene becoming active, not another background tick.
    @MainActor
    func testUnlockAfterWallTimePassedTheSpanEndEndsTheActivity() async throws {
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
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        model.wallNow = { origin }
        model.setSceneActive(false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertTrue(fake.ended.isEmpty)
        XCTAssertEqual(model.utc, parked)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)

        model.wallNow = { origin.addingTimeInterval(40) }
        model.setSceneActive(true)
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

    /// Replay dismisses the card that was already up, then pushes the span start. It does not keep the old instant.
    @MainActor
    func testReplayClearsTheStaleActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.utc = span.start.addingTimeInterval(5)
        model.ended = true
        model.playing = false
        model.replay()
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 0, accuracy: 0.001)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        let state = try XCTUnwrap(fake.lastState)
        XCTAssertEqual(state.clock, "at 19:33:00 UTC")
        XCTAssertEqual(state.elapsedText, "0:00 into the flyby")
        XCTAssertTrue(state.playing)
    }

    /// A date past the span end, the way a fast flick's predicted end lands, parks at end − 8s.
    @MainActor
    func testFlickPastTheEndParksShortOfTheSpanEnd() throws {
        let model = PlaybackModel()
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.beginScrub()
        model.scrubRuler(to: span.start.addingTimeInterval(40))
        model.scrubRuler(to: span.end.addingTimeInterval(12))
        model.endScrub(markEnd: false)
        XCTAssertEqual(model.utc.timeIntervalSince(span.end.addingTimeInterval(-PlaybackModel.scrubEndMargin)), 0, accuracy: 0.001)
        XCTAssertFalse(model.ended)
        XCTAssertTrue(model.playing)
        XCTAssertEqual(model.range, .flyby)
    }

    /// A memory warning may retry decodes. Those completions must not push the Live Activity on every frame.
    @MainActor
    func testMemoryWarningKeepsTheLiveActivityCadence() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.playing = true
        let span = try XCTUnwrap(model.activeSpan)
        model.seek(to: span.start.addingTimeInterval(30))
        await FlybyLiveActivity.finishQueuedWork()
        let file = try XCTUnwrap(model.pair(for: model.window).current?.file)

        let stamp = CACurrentMediaTime()
        let calmStart = fake.updatedPlaying.count
        for _ in 0..<30 {
            model.advanceDisplayLinkForTest(to: stamp)
        }
        await FlybyLiveActivity.finishQueuedWork()
        let calm = fake.updatedPlaying.count - calmStart
        XCTAssertEqual(calm, 0, "ordinary ticks pushed \(calm) times")

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        MediaStore.allowRetries()
        let warned = fake.updatedPlaying.count
        for _ in 0..<60 {
            model.noteFramesDecoded(file: file)
        }
        for _ in 0..<30 {
            model.advanceDisplayLinkForTest(to: stamp)
        }
        await FlybyLiveActivity.finishQueuedWork()
        let pushed = fake.updatedPlaying.count - warned
        XCTAssertEqual(pushed, 0, "memory warning pushed \(pushed) times across 60 decodes and 30 ticks")
    }

    /// The purge drops the spare pin and keeps the bitmap that was on screen.
    @MainActor
    func testMemoryWarningKeepsTheDisplayedFrame() {
        let shown = Self.solidImage(UIColor(white: 0.9, alpha: 1))
        let spare = Self.solidImage(UIColor(white: 0.1, alpha: 1))
        MediaStore.stage(image: spare, file: "images/spare.webp", maxPixel: 800)
        MediaStore.stage(image: shown, file: "images/shown.webp", maxPixel: 800)

        MediaStore.allowRetries()

        let kept = MediaStore.cachedImage(file: "images/shown.webp", small: false, maxPixel: 800)
        XCTAssertTrue(kept === shown)
        XCTAssertNil(MediaStore.cachedImage(file: "images/spare.webp", small: false, maxPixel: 800))
    }

    /// Replay parks in the gap before the first file. Locking there used to leave the clock on
    /// display-link time, which crawls while the screen is off. The locked gap follows wall time.
    @MainActor
    func testLockRightAfterReplayFollowsWallTime() async throws {
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.utc = span.start.addingTimeInterval(120)
        let origin = Date(timeIntervalSince1970: 1_800_000_000)
        model.wallNow = { origin }
        model.replay()
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 0, accuracy: 0.001)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)

        model.setSceneActive(false)
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 0, accuracy: 0.05)
        XCTAssertFalse(model.ended)

        model.wallNow = { origin.addingTimeInterval(18) }
        model.backgroundTick()
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 18, accuracy: 0.05)
        XCTAssertTrue(model.playing)
        XCTAssertFalse(model.ended)
        XCTAssertLessThan(model.utc, span.end)
    }

    /// Identical states drop. A non-immediate update inside 1 s waits, then the flush sends it.
    /// An immediate update in that same window goes out.
    @MainActor
    func testThrottleDropsIdenticalDefersAndLetsImmediateThrough() async {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock: @MainActor () -> Date = { now }

        func push(clockText: String, playing: Bool, immediate: Bool) {
            FlybyLiveActivity.sync(
                arrived: true,
                playing: playing,
                progress: 0.1,
                nextMilestone: "End of this span",
                speaker: "Wiseman",
                clock: clockText,
                elapsedText: "0:30 into the flyby",
                staleDate: now.addingTimeInterval(60),
                immediate: immediate,
                now: clock
            )
        }

        push(clockText: "at 19:33:30 UTC", playing: true, immediate: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, 1)
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:30 UTC")

        push(clockText: "at 19:33:30 UTC", playing: true, immediate: false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, 1)

        now = now.addingTimeInterval(0.4)
        push(clockText: "at 19:33:31 UTC", playing: true, immediate: false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, 1)
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:30 UTC")

        await FlybyLiveActivity.flushPending()
        XCTAssertEqual(fake.updatedPlaying.count, 1)
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:30 UTC")

        now = now.addingTimeInterval(0.7)
        await FlybyLiveActivity.flushPending()
        XCTAssertEqual(fake.updatedPlaying.count, 2)
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:31 UTC")
        XCTAssertEqual(fake.lastState?.playing, true)

        now = now.addingTimeInterval(0.2)
        push(clockText: "at 19:33:32 UTC", playing: false, immediate: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, 3)
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:32 UTC")
        XCTAssertEqual(fake.lastState?.playing, false)
    }

    /// While playing, the lock-screen strings go out again once the injected clock has moved 8 s.
    @MainActor
    func testPlayingPushesAgainAfterEightSeconds() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.wallNow = { now }
        model.playing = true
        let timeline = try XCTUnwrap(model.timeline)
        let quiet = try ISO8601.parse("2026-04-06T19:34:30Z")
        let milestones = MilestoneList.derive(timeline)
        let nextAtQuiet = FlybyActivityCopy.nextLabel(after: quiet, milestones: milestones)
        XCTAssertEqual(nextAtQuiet, FlybyActivityCopy.nextLabel(after: quiet.addingTimeInterval(8), milestones: milestones))
        let lines = timeline.lines
        let speaker = LyricFocus.focus(at: quiet, track: model.trackID, lines: lines).current?.speaker
        XCTAssertEqual(speaker, LyricFocus.focus(at: quiet.addingTimeInterval(8), track: model.trackID, lines: lines).current?.speaker)

        model.seek(to: quiet)
        await FlybyLiveActivity.finishQueuedWork()
        let pushed = fake.updatedPlaying.count
        XCTAssertGreaterThan(pushed, 0)
        XCTAssertEqual(fake.lastState?.clock, "at 19:34:30 UTC")

        model.advanceDisplayLinkForTest(to: 10_000)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, pushed)

        now = now.addingTimeInterval(7)
        model.advanceDisplayLinkForTest(to: 10_007)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, pushed)
        XCTAssertEqual(fake.lastState?.clock, "at 19:34:30 UTC")

        now = now.addingTimeInterval(1)
        model.advanceDisplayLinkForTest(to: 10_008)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, pushed + 1)
        XCTAssertEqual(fake.lastState?.clock, "at 19:34:38 UTC")
        XCTAssertEqual(fake.lastState?.playing, true)
    }

    /// Pause, then +15 s inside the 1 s window. The card takes the new instant without waiting to be flushed.
    @MainActor
    func testPausedSeekLandsInsideTheThrottleWindow() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.wallNow = { now }
        model.playing = true
        let span = try XCTUnwrap(model.activeSpan)
        model.pause(user: true)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:00 UTC")
        XCTAssertEqual(fake.lastState?.playing, false)
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 0, accuracy: 0.001)

        now = now.addingTimeInterval(0.4)
        model.skip(by: 15)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.lastState?.clock, "at 19:33:15 UTC")
        XCTAssertEqual(fake.lastState?.elapsedText, "0:15 into the flyby")
        XCTAssertEqual(fake.lastState?.playing, false)
        XCTAssertEqual(model.utc.timeIntervalSince(span.start), 15, accuracy: 0.001)
        XCTAssertFalse(model.playing)
    }

    /// A decode that finishes while paused may refresh Now Playing art. It must not push the Live Activity.
    @MainActor
    func testPausedDecodeDoesNotPushTheLiveActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        model.playing = true
        model.pause(user: true)
        await FlybyLiveActivity.finishQueuedWork()
        let pushed = fake.updatedPlaying.count
        let file = model.pair(for: model.window).current?.file ?? "images/art002e016184.webp"
        model.noteFramesDecoded(file: file)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.updatedPlaying.count, pushed)
        XCTAssertFalse(model.playing)
    }

    private static func solidImage(_ color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}
