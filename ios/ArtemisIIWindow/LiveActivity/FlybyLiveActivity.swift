import ActivityKit
import Foundation

enum FlybyActivityCopy {
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    static func nextLabel(after date: Date, milestones: [Milestone]) -> String {
        milestones.first { $0.date > date }?.label ?? "End of this span"
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum FlybyLiveActivity {
    @MainActor
    static func sync(
        arrived: Bool,
        playing: Bool,
        progress: Double,
        nextMilestone: String,
        speaker: String,
        clock: String
    ) {
        guard arrived else { return }
        let state = FlybyActivityAttributes.ContentState(
            progress: progress,
            nextMilestone: nextMilestone,
            speaker: speaker,
            clock: clock
        )
        let content = ActivityContent(state: state, staleDate: nil)
        if let existing = Activity<FlybyActivityAttributes>.activities.first {
            Task { await existing.update(content) }
        } else if playing {
            _ = try? Activity.request(
                attributes: FlybyActivityAttributes(title: "Orion Window"),
                content: content,
                pushType: nil
            )
        }
    }
}
