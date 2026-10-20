import Foundation

/// Shared with the widget. ActivityKit conformance lives next to the system client and in the widget, so this file does not import ActivityKit.
struct FlybyActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        /// Absolute mission UTC, `at HH:mm:ss UTC`, from the last push. The lock screen shows this string.
        /// VoiceOver reads it. It is not a `Text(timerInterval:)`.
        var clock: String
        var playing: Bool
        /// Wall interval whose elapsed time is `utc - span.start`. The lock screen ticks this only while playing.
        /// `elapsedText` is that same count as `mm:ss into the flyby`, used while paused and for VoiceOver.
        var elapsedStart: Date
        var elapsedEnd: Date
        var elapsedText: String
    }

    /// Lock Screen and Dynamic Island copy. Nil while the recording is playing.
    static func pausedLabel(playing: Bool) -> String? {
        playing ? nil : "Paused"
    }

    var title: String
}
