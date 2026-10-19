import Foundation

/// Shared with the widget. ActivityKit conformance lives next to the system client and in the widget, so this file does not import ActivityKit.
struct FlybyActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        /// Absolute mission UTC, `at HH:mm:ss UTC`. The lock screen shows this string. It does not use a timer interval.
        var clock: String
        var playing: Bool
    }

    var title: String
}
