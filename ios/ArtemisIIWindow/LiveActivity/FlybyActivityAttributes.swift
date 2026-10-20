import Foundation

/// Shared with the widget. ActivityKit conformance lives next to the system client and in the widget, so this file does not import ActivityKit.
struct FlybyActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        /// Absolute mission UTC, `at HH:mm:ss UTC`. VoiceOver reads this. The lock screen draws `clockStart`.
        var clock: String
        var playing: Bool
        /// Wall-clock count whose elapsed time is the mission `HH:mm:ss`. It ticks while the app is suspended.
        /// `clockPause` freezes that count while playback is paused.
        var clockStart: Date
        var clockEnd: Date
        var clockPause: Date?
    }

    /// Lock Screen and Dynamic Island copy. Nil while the recording is playing.
    static func pausedLabel(playing: Bool) -> String? {
        playing ? nil : "Paused"
    }

    var title: String
}
