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
    /// Ends and updates run one at a time, in the order they were scheduled.
    /// Each one awaits the previous item, so `Activity.request` cannot start while `endAllImmediately` is still dismissing.
    @MainActor
    private static var chain: Task<Void, Never>?

    /// Ends every activity this process can still see, including one left up after a previous launch.
    /// The activity lookup stays on the main actor. Callers that cannot wait use `scheduleEndAllImmediately()`, which is the same dismissal registered before it returns.
    @MainActor
    static func endAllImmediately() async {
        await scheduleEndAllImmediately().value
    }

    /// Registers the dismissal on the chain before returning. `sync` runs only after this task finishes.
    @MainActor
    @discardableResult
    static func scheduleEndAllImmediately() -> Task<Void, Never> {
        enqueue {
            for activity in Activity<FlybyActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    @MainActor
    static func sync(
        arrived: Bool,
        playing: Bool,
        progress: Double,
        nextMilestone: String,
        speaker: String,
        clock: String,
        staleDate: Date?
    ) {
        enqueue {
            guard RuntimeHost.allowsPlaybackServices(), arrived, playing else {
                for activity in Activity<FlybyActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                return
            }
            let state = FlybyActivityAttributes.ContentState(
                progress: progress,
                nextMilestone: nextMilestone,
                speaker: speaker,
                clock: clock
            )
            let content = ActivityContent(state: state, staleDate: staleDate)
            if Activity<FlybyActivityAttributes>.activities.isEmpty {
                _ = try? Activity.request(
                    attributes: FlybyActivityAttributes(title: "Orion Window"),
                    content: content,
                    pushType: nil
                )
                return
            }
            await Activity<FlybyActivityAttributes>.activities.first?.update(content)
        }
    }

    @MainActor
    @discardableResult
    private static func enqueue(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = chain
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        chain = task
        return task
    }
}
