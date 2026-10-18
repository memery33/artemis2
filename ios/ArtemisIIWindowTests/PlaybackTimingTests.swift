import XCTest
@testable import ArtemisIIWindow

final class PlaybackTimingTests: XCTestCase {
    func testFutureScheduleDoesNotCountTheGap() {
        let lead = 8.718
        let intoFile = 12.4
        let position = PlaybackTiming.fileSeconds(
            scheduledStart: 0,
            playerSeconds: lead + intoFile,
            lead: lead
        )
        XCTAssertEqual(position, intoFile, accuracy: 0.0001)
    }

    func testFutureScheduleClampsDuringTheWait() {
        let position = PlaybackTiming.fileSeconds(scheduledStart: 0, playerSeconds: 2, lead: 9)
        XCTAssertEqual(position, 0)
        XCTAssertGreaterThanOrEqual(position, 0)
    }

    func testGapIsNotCountedAgainstTheFileTail() {
        let lead = 9.0
        let fileDuration = 40.0
        let intoFile = 31.0
        let playerSeconds = lead + intoFile
        let position = PlaybackTiming.fileSeconds(scheduledStart: 0, playerSeconds: playerSeconds, lead: lead)
        XCTAssertEqual(position, intoFile, accuracy: 0.0001)
        XCTAssertLessThan(position, fileDuration)
        XCTAssertGreaterThanOrEqual(playerSeconds, fileDuration)
    }

    func testHostTimeOnlyHoldsTheClockDuringTheWait() {
        let duringWait = PlaybackTiming.fileSeconds(
            scheduledStart: 0,
            playerSeconds: 4,
            lead: 9,
            renderHostSeconds: 1_000,
            audibleHostSeconds: 1_009
        )
        XCTAssertEqual(duringWait, 0)

        let playing = PlaybackTiming.fileSeconds(
            scheduledStart: 0,
            playerSeconds: 9 + 3,
            lead: 9,
            renderHostSeconds: 1_012,
            audibleHostSeconds: 1_009
        )
        XCTAssertEqual(playing, 3, accuracy: 0.0001)
    }

    func testPauseAfterTheGapDoesNotFollowHostTime() {
        let lead = 9.0
        let intoFile = 11.0
        let pause = 30.0
        let position = PlaybackTiming.fileSeconds(
            scheduledStart: 0,
            playerSeconds: lead + intoFile,
            lead: lead,
            renderHostSeconds: 1_009 + intoFile + pause,
            audibleHostSeconds: 1_009
        )
        XCTAssertEqual(position, intoFile, accuracy: 0.0001)
        XCTAssertNotEqual(position, intoFile + pause)
    }

    func testImmediatePlaybackKeepsTheScheduledOffset() {
        let position = PlaybackTiming.fileSeconds(scheduledStart: 4, playerSeconds: 12.5, lead: 0)
        XCTAssertEqual(position, 16.5, accuracy: 0.0001)
    }

    func testRecoveryUsesMissionTimeClampedToTheFile() {
        XCTAssertEqual(PlaybackTiming.recoveryOffset(missionSeconds: 40, fileDuration: 100), 40)
        XCTAssertEqual(PlaybackTiming.recoveryOffset(missionSeconds: -2, fileDuration: 100), 0)
        XCTAssertEqual(PlaybackTiming.recoveryOffset(missionSeconds: 140, fileDuration: 100), 100)
        XCTAssertEqual(PlaybackTiming.recoveryOffset(missionSeconds: 10, fileDuration: 0), 0)
        XCTAssertEqual(PlaybackTiming.recoveryOffset(missionSeconds: 100, fileDuration: 100), 100)
    }

    func testRecoveryIgnoresAnOvershotRenderClock() {
        let lead = 9.0
        let missionSeconds = 40.0
        let overshotRenderClock = missionSeconds + lead
        let fileDuration = 100.0
        let resumed = PlaybackTiming.recoveryOffset(missionSeconds: missionSeconds, fileDuration: fileDuration)
        XCTAssertEqual(resumed, missionSeconds)
        XCTAssertNotEqual(resumed, overshotRenderClock)
        XCTAssertLessThan(resumed, fileDuration)
    }

    func testLockedRecoveryUsesTheLiveSampleNotTheStaleClock() {
        let position = PlaybackTiming.recoveryOffset(
            missionSeconds: 10,
            fileDuration: 100,
            liveRenderSeconds: 47
        )
        XCTAssertEqual(position, 47)
        XCTAssertNotEqual(position, 10)
    }

    func testLockedRecoveryWithoutARenderClockUsesMissionTime() {
        XCTAssertEqual(
            PlaybackTiming.recoveryOffset(missionSeconds: 10, fileDuration: 100, liveRenderSeconds: nil),
            10
        )
    }

    func testPauseAfterAudibleFileClearsTheArm() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let paused = PlaybackTiming.clockAfterPause(
            segmentStart: start,
            segmentEnd: start.addingTimeInterval(40),
            renderedSeconds: 12.5,
            holdSeconds: 0,
            holdUntil: start,
            utc: start.addingTimeInterval(-9),
            remainingWait: nil,
            nodeWasPlaying: true
        )
        XCTAssertNil(paused.holdUntil)
        XCTAssertEqual(paused.utc, start.addingTimeInterval(12.5))
        XCTAssertEqual(paused.holdSeconds, 12.5, accuracy: 0.0001)
        XCTAssertTrue(paused.resetWallClock)
    }

    func testPauseBeforeAudibleKeepsTheRemainingWait() {
        let start = Date(timeIntervalSince1970: 1_000)
        let paused = PlaybackTiming.clockAfterPause(
            segmentStart: start,
            segmentEnd: start.addingTimeInterval(40),
            renderedSeconds: 0,
            holdSeconds: 0,
            holdUntil: start,
            utc: start.addingTimeInterval(-9),
            remainingWait: 4,
            nodeWasPlaying: true
        )
        XCTAssertEqual(paused.holdUntil, start)
        XCTAssertEqual(paused.utc, start.addingTimeInterval(-4))
        XCTAssertEqual(paused.holdSeconds, 0)
        XCTAssertEqual(paused.holdUntil?.timeIntervalSince(paused.utc) ?? 0, 4, accuracy: 0.0001)
        XCTAssertTrue(paused.resetWallClock)
        XCTAssertEqual(PlaybackTiming.remainingWait(nowHostSeconds: 1_005, audibleHostSeconds: 1_009), 4)
    }

    func testAudibleRecoveryClearsTheArm() {
        let plan = PlaybackTiming.recoveryPlan(
            liveRenderSeconds: 47,
            secondsUntilArm: 9,
            missionSeconds: 10,
            fileDuration: 100
        )
        XCTAssertEqual(plan, .resumeFile(position: 47, clearHoldUntil: true))
    }

    func testSilentRecoveryRearmsTheRemainingGap() {
        let plan = PlaybackTiming.recoveryPlan(
            liveRenderSeconds: 0,
            secondsUntilArm: 4,
            missionSeconds: 0,
            fileDuration: 100
        )
        XCTAssertEqual(plan, .rearmGap(delay: 4))
    }

    func testPauseMidGapLeavesTheClock() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(40)
        let utc = end.addingTimeInterval(12)
        let paused = PlaybackTiming.clockAfterPause(
            segmentStart: start,
            segmentEnd: end,
            renderedSeconds: 40,
            holdSeconds: 40,
            holdUntil: nil,
            utc: utc,
            remainingWait: nil,
            nodeWasPlaying: false
        )
        XCTAssertEqual(paused.utc, utc)
        XCTAssertNil(paused.holdUntil)
        XCTAssertEqual(paused.holdSeconds, 40, accuracy: 0.0001)
        XCTAssertFalse(paused.resetWallClock)
    }

    func testLockedGapRecoveryUsesHostWaitNotTheStaleClock() {
        let delay = PlaybackTiming.gapDelay(remainingWait: 4, armedOffset: 30)
        XCTAssertEqual(delay, 4)
        XCTAssertNotEqual(delay, 30)
        XCTAssertEqual(PlaybackTiming.gapDelay(remainingWait: 0, armedOffset: 30), 0)
        XCTAssertEqual(PlaybackTiming.gapDelay(remainingWait: nil, armedOffset: 6), 6)
        let plan = PlaybackTiming.recoveryPlan(
            liveRenderSeconds: 0,
            secondsUntilArm: delay,
            missionSeconds: 0,
            fileDuration: 100
        )
        XCTAssertEqual(plan, .rearmGap(delay: 4))
    }

    func testExpiredArmClearsHoldUntil() {
        let due = PlaybackTiming.recoveryPlan(
            liveRenderSeconds: 0,
            secondsUntilArm: 0,
            missionSeconds: 10,
            fileDuration: 100
        )
        XCTAssertEqual(due, .resumeFile(position: 10, clearHoldUntil: true))
        let past = PlaybackTiming.recoveryPlan(
            liveRenderSeconds: nil,
            secondsUntilArm: -2,
            missionSeconds: 10,
            fileDuration: 100
        )
        XCTAssertEqual(past, .resumeFile(position: 10, clearHoldUntil: true))
    }
}
