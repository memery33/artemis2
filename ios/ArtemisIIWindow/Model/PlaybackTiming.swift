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
}
