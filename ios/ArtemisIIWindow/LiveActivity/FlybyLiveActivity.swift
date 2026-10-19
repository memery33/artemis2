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

/// Used while this process is the unit-test host. It never calls ActivityKit.
@MainActor
final class SilentFlybyActivities: FlybyActivityClient {
    func identifiers() -> [String] { [] }
    func end(identifiers: [String]) async {}
    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {}
    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {}
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
    static var client: any FlybyActivityClient = RuntimeHost.isUnitTestHost
        ? SilentFlybyActivities()
        : SystemFlybyActivities()

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
    /// The unit-test host's client is silent, so this does not touch ActivityKit there.
    @MainActor
    @discardableResult
    static func scheduleEndAllImmediately() -> Task<Void, Never> {
        let ids = client.identifiers()
        return enqueue {
            await client.end(identifiers: ids)
        }
    }

    /// Ends every activity and does not return until that end has finished.
    /// Launch calls this before the player exists. The unit-test host skips it.
    @MainActor
    static func finishLaunchCleanup() {
        guard !RuntimeHost.isUnitTestHost else { return }
        let gate = LaunchCleanup()
        enqueue {
            let ids = client.identifiers()
            await client.end(identifiers: ids)
            gate.finish()
        }
        let deadline = Date().addingTimeInterval(2)
        while !gate.isFinished, Date() < deadline {
            RunLoop.current.run(mode: .common, before: Date().addingTimeInterval(0.05))
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
                hourText: FlybyActivityAttributes.ContentState.hourText(for: utcStart),
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

/// Lets launch wait until the dismissal task has finished without leaving the main actor.
private final class LaunchCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }
}
