import ActivityKit
import Foundation

struct FlybyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        /// Mission UTC as `HH:mm:ss`, used while playback is paused.
        var clock: String
        /// Hour prefix, including the colon, so the ticking minute timer can show real seconds.
        var hourText: String
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
    /// Minute-and-second count-up. The elapsed time stays under an hour, so the Live Activity
    /// draws real seconds and advances with the wall clock instead of a coarse `HH:mm:--` timer.
    var missionTimer: ClosedRange<Date> {
        let parts = Self.utcParts(utcStart)
        let seconds = TimeInterval(parts.minute * 60 + parts.second)
        let start = wallStart.addingTimeInterval(-seconds)
        return start...start.addingTimeInterval(3599)
    }

    static func hourText(for date: Date) -> String {
        String(format: "%02d:", utcParts(date).hour)
    }

    private static func utcParts(_ date: Date) -> (hour: Int, minute: Int, second: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
