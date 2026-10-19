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
        let state = FlybyActivityAttributes.ContentState(
            progress: 0.2,
            nextMilestone: "End of this span",
            speaker: "Wiseman",
            clock: text,
            playing: true
        )
        XCTAssertEqual(state.clock, "at 19:38:45 UTC")
        XCTAssertFalse(state.clock.contains("--"))
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
        model.currentFile = segment.file
        model.holdSeconds = span.end.timeIntervalSince(segment.start) + 5
        model.segmentDidFinish()
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
        model.tickOnMain(1)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertTrue(model.ended)
        XCTAssertEqual(model.utc, span.end)
    }

    /// Background playback with nothing left in the span dismisses the activity.
    @MainActor
    func testBackgroundSpanEndEndsTheActivity() async throws {
        let fake = FakeFlybyActivities(identifiers: ["live"])
        let previous = FlybyLiveActivity.install(fake)
        defer { FlybyLiveActivity.install(previous) }
        let model = PlaybackModel()
        model.arrived = true
        model.postsLiveActivityWhileSkippingAudio = true
        let span = try XCTUnwrap(model.activeSpan)
        model.playing = true
        model.utc = span.end.addingTimeInterval(5)
        model.setSceneActive(false)
        await FlybyLiveActivity.finishQueuedWork()
        XCTAssertEqual(fake.ended, ["live"])
        XCTAssertTrue(fake.identifiersStore.isEmpty)
        XCTAssertTrue(model.ended)
        XCTAssertEqual(model.utc, span.end)
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
