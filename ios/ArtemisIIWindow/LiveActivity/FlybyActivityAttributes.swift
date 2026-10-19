import ActivityKit
import Foundation

struct FlybyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        /// Mission UTC as `HH:mm:ss`, used while playback is paused.
        var clock: String
        /// While playing, the widget counts this anchor up instead of waiting for the app to push a new string.
        var playing: Bool
        /// Mission time at `wallStart`.
        var utcStart: Date
        /// Wall-clock time when `utcStart` was sampled.
        var wallStart: Date
    }

    var title: String
}

extension FlybyActivityAttributes.ContentState {
    /// A count-up timer that reads the mission UTC time of day at `wallStart` and keeps ticking with the wall clock.
    var missionTimer: ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.hour, .minute, .second], from: utcStart)
        let seconds = TimeInterval((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
        let start = wallStart.addingTimeInterval(-seconds)
        return start...start.addingTimeInterval(48 * 60 * 60)
    }
}
