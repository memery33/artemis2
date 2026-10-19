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

    func testMissionTimerIsAnchoredToUTCAndWallClock() throws {
        let utc = try ISO8601.parse("2026-04-06T19:33:01Z")
        let wall = Date(timeIntervalSince1970: 1_700_000_000)
        let state = FlybyActivityAttributes.ContentState(
            progress: 0.2,
            nextMilestone: "End of this span",
            speaker: "Wiseman",
            clock: "19:33:01",
            hourText: "19:",
            playing: true,
            utcStart: utc,
            wallStart: wall
        )
        XCTAssertEqual(FlybyActivityAttributes.ContentState.hourText(for: utc), "19:")
        XCTAssertEqual(state.hourText, "19:")
        let minuteSeconds = TimeInterval(33 * 60 + 1)
        XCTAssertEqual(state.missionTimer.lowerBound.timeIntervalSince(wall), -minuteSeconds, accuracy: 0.5)
        XCTAssertEqual(
            state.missionTimer.upperBound.timeIntervalSince(state.missionTimer.lowerBound),
            3599,
            accuracy: 0.5
        )
        XCTAssertLessThan(minuteSeconds, 3600)
    }

    @MainActor
    func testUnitTestHostStartsWithASilentActivityClient() {
        XCTAssertTrue(FlybyLiveActivity.client is SilentFlybyActivities)
    }
}
