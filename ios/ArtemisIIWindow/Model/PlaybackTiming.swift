import Foundation

/// Pure clock math for playback. No audio objects, so the tests can run the cases
/// that depend on a future schedule and on an engine that has already stopped.
enum PlaybackTiming {
    /// Seconds into the file.
    ///
    /// `playerSeconds` is `sampleTime / sampleRate`. A segment scheduled in the
    /// future still starts the node immediately, so that value includes the
    /// silent wait (`lead`). Host time tells us whether that wait is over.
    /// Once the file is audible, the sample clock is the position: it stops
    /// while the node is paused, and host time does not. The result is never negative.
    static func fileSeconds(
        scheduledStart: TimeInterval,
        playerSeconds: TimeInterval,
        lead: TimeInterval,
        renderHostSeconds: TimeInterval? = nil,
        audibleHostSeconds: TimeInterval? = nil
    ) -> TimeInterval {
        if let renderHostSeconds, let audibleHostSeconds, renderHostSeconds < audibleHostSeconds {
            return 0
        }
        return max(0, scheduledStart + playerSeconds - lead)
    }

    /// Where to put the playhead after the engine has stopped the node.
    /// A live render sample wins over mission time, which can be stale while
    /// the display link is paused. Either value is clamped to the file.
    static func recoveryOffset(
        missionSeconds: TimeInterval,
        fileDuration: TimeInterval,
        liveRenderSeconds: TimeInterval? = nil
    ) -> TimeInterval {
        let duration = max(0, fileDuration)
        let raw = liveRenderSeconds ?? missionSeconds
        return min(max(0, raw), duration)
    }

    /// Host time left before a future-scheduled file becomes audible.
    static func remainingWait(nowHostSeconds: TimeInterval, audibleHostSeconds: TimeInterval) -> TimeInterval {
        max(0, audibleHostSeconds - nowHostSeconds)
    }

    struct PausedClock: Equatable {
        var utc: Date
        var holdUntil: Date?
        var holdSeconds: TimeInterval
        var resetWallClock: Bool
    }

    /// Pause while a locked gap is still armed.
    /// Once the file is audible, mission time becomes that sample and the arm is cleared
    /// so resume does not schedule the file from 0:00. Before it is audible, mission time
    /// moves forward only by the wait that has already elapsed.
    static func clockAfterPause(
        segmentStart: Date,
        segmentEnd: Date,
        renderedSeconds: TimeInterval,
        holdUntil: Date?,
        utc: Date,
        remainingWait: TimeInterval?
    ) -> PausedClock {
        if renderedSeconds > 0 {
            let span = max(0, segmentEnd.timeIntervalSince(segmentStart))
            let position = min(max(0, renderedSeconds), span)
            return PausedClock(
                utc: segmentStart.addingTimeInterval(position),
                holdUntil: nil,
                holdSeconds: position,
                resetWallClock: true
            )
        }
        if let remainingWait, let holdUntil {
            if remainingWait > 0 {
                return PausedClock(
                    utc: holdUntil.addingTimeInterval(-remainingWait),
                    holdUntil: holdUntil,
                    holdSeconds: 0,
                    resetWallClock: true
                )
            }
            return PausedClock(
                utc: holdUntil,
                holdUntil: nil,
                holdSeconds: 0,
                resetWallClock: true
            )
        }
        return PausedClock(utc: utc, holdUntil: holdUntil, holdSeconds: 0, resetWallClock: false)
    }

    enum RecoveryPlan: Equatable {
        case rearmGap(delay: TimeInterval)
        case resumeFile(position: TimeInterval, clearHoldUntil: Bool)
    }

    /// A live sample means the file is already audible. The arm has to come down
    /// or the next file never loads. A silent node with time left in the gap re-arms it.
    static func recoveryPlan(
        liveRenderSeconds: TimeInterval?,
        secondsUntilArm: TimeInterval?,
        missionSeconds: TimeInterval,
        fileDuration: TimeInterval
    ) -> RecoveryPlan {
        if (liveRenderSeconds ?? 0) <= 0, let secondsUntilArm, secondsUntilArm > 0 {
            return .rearmGap(delay: secondsUntilArm)
        }
        return .resumeFile(
            position: recoveryOffset(
                missionSeconds: missionSeconds,
                fileDuration: fileDuration,
                liveRenderSeconds: liveRenderSeconds
            ),
            clearHoldUntil: (liveRenderSeconds ?? 0) > 0
        )
    }
}
