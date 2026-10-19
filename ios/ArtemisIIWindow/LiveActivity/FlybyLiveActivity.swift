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

    @MainActor
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @MainActor
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }
}

/// The app talks to ActivityKit through this so a unit test can run the end path without a Live Activity.
@MainActor
protocol FlybyActivityClient: AnyObject {
    func identifiers() -> [String]
    func end(identifiers: [String]) async
    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async
    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async
}

@MainActor
final class SystemFlybyActivities: FlybyActivityClient {
    func identifiers() -> [String] {
        Activity<FlybyActivityAttributes>.activities.map(\.id)
    }

    func end(identifiers: [String]) async {
        let ending = Set(identifiers)
        for activity in Activity<FlybyActivityAttributes>.activities where ending.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        _ = try? Activity.request(
            attributes: FlybyActivityAttributes(title: "Orion Window"),
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: nil
        )
    }

    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {
        await Activity<FlybyActivityAttributes>.activities.first?.update(
            ActivityContent(state: state, staleDate: staleDate)
        )
    }
}

enum FlybyLiveActivity {
    /// Ends and updates run one at a time. An end only dismisses the ids captured when it was scheduled.
    @MainActor
    private static var chain: Task<Void, Never>?

    @MainActor
    static var client: any FlybyActivityClient = SystemFlybyActivities()

    @MainActor
    static var isRunning: Bool {
        !client.identifiers().isEmpty
    }

    /// Swaps the ActivityKit client. Returns the previous one so a test can restore it.
    @MainActor
    @discardableResult
    static func install(_ replacement: any FlybyActivityClient) -> any FlybyActivityClient {
        let previous = client
        client = replacement
        return previous
    }

    /// Ends every activity visible on this turn, including one left up after a previous launch.
    /// The id list is taken before the first await, so an activity requested afterwards is left alone.
    @MainActor
    static func endAllImmediately() async {
        await scheduleEndAllImmediately().value
    }

    /// Registers the dismissal before returning. `sync` is queued behind it.
    @MainActor
    @discardableResult
    static func scheduleEndAllImmediately() -> Task<Void, Never> {
        let ids = client.identifiers()
        return enqueue {
            await client.end(identifiers: ids)
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
        utcStart: Date,
        wallStart: Date,
        staleDate: Date?
    ) {
        enqueue {
            let state = FlybyActivityAttributes.ContentState(
                progress: progress,
                nextMilestone: nextMilestone,
                speaker: speaker,
                clock: clock,
                playing: playing,
                utcStart: utcStart,
                wallStart: wallStart
            )
            guard RuntimeHost.allowsPlaybackServices(), arrived, playing else {
                let ids = client.identifiers()
                await client.end(identifiers: ids)
                return
            }
            if client.identifiers().isEmpty {
                await client.request(state, staleDate: staleDate)
                return
            }
            await client.update(state, staleDate: staleDate)
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
