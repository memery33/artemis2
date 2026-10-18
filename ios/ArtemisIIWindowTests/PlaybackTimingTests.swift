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

    func testLiveRenderIsClampedToTheFile() {
        XCTAssertEqual(
            PlaybackTiming.recoveryOffset(missionSeconds: 10, fileDuration: 100, liveRenderSeconds: 140),
            100
        )
        XCTAssertEqual(
            PlaybackTiming.recoveryOffset(missionSeconds: 10, fileDuration: 100, liveRenderSeconds: -3),
            0
        )
    }
}
