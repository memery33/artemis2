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

    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        _ = (state, staleDate)
    }

    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        _ = (state, staleDate)
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

    func testStaleDateIsOneMinuteAfterTheSpanEnd() throws {
        let end = try ISO8601.parse("2026-04-06T19:48:30Z")
        XCTAssertEqual(FlybyActivityCopy.staleDate(spanEnd: end).timeIntervalSince(end), 60, accuracy: 0.001)
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
}
