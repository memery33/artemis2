import Foundation

/// Pure clock math for playback. No audio objects, so the tests can run the cases
/// that depend on a future schedule and on an engine that has already stopped.
enum PlaybackTiming {
    /// Seconds into the file.
    ///
    /// `playerSeconds` is `sampleTime / sampleRate`. A segment scheduled in the
    /// future still starts the node immediately, so that value includes the
    /// silent wait (`lead`). Host times, when both are known, are the render
    /// clock and the host time at which the file should become audible.
    /// The result is never negative.
    static func fileSeconds(
        scheduledStart: TimeInterval,
        playerSeconds: TimeInterval,
        lead: TimeInterval,
        renderHostSeconds: TimeInterval? = nil,
        audibleHostSeconds: TimeInterval? = nil
    ) -> TimeInterval {
        if let renderHostSeconds, let audibleHostSeconds {
            return max(0, scheduledStart + renderHostSeconds - audibleHostSeconds)
        }
        return max(0, scheduledStart + playerSeconds - lead)
    }

    /// Where to put the playhead after the engine has stopped the node.
    /// `missionSeconds` is `utc - segment.start`. It is clamped to the file.
    static func recoveryOffset(missionSeconds: TimeInterval, fileDuration: TimeInterval) -> TimeInterval {
        let duration = max(0, fileDuration)
        return min(max(0, missionSeconds), duration)
    }
}
