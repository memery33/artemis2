import Foundation

enum FlybyActivityCopy {
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    static func nextLabel(after date: Date, milestones: [Milestone]) -> String {
        milestones.first { $0.date > date }?.label ?? "End of this span"
    }

    /// Wall-clock stale date. The mission span is April 2026, so a stale date of `spanEnd + 60s` is already past and SpringBoard drops the activity.
    /// While playing, the activity stays fresh for the remaining mission time at `rate`, plus one minute. While paused, it stays fresh for 15 minutes.
    static func staleDate(now: Date = Date(), playing: Bool, utc: Date, spanEnd: Date, rate: Double) -> Date {
        guard playing else { return now.addingTimeInterval(15 * 60) }
        let speed = rate > 0 ? rate : 1
        let remaining = max(0, spanEnd.timeIntervalSince(utc) / speed)
        return now.addingTimeInterval(remaining + 60)
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

    /// Lock-screen line. The card shows this string. It changes when playback pushes, not by counting.
    @MainActor
    static func lockScreenClock(_ date: Date) -> String {
        "at \(clock(date)) UTC"
    }

    /// UTC line and elapsed line from one mission instant. Elapsed is `utc - spanStart`.
    /// Both playing and paused show this string. It does not tick on its own.
    struct Reading: Equatable, Sendable {
        var clock: String
        var elapsedText: String
    }

    @MainActor
    static func reading(utc: Date, spanStart: Date, phrase: String) -> Reading {
        let elapsed = max(0, utc.timeIntervalSince(spanStart))
        return Reading(clock: lockScreenClock(utc), elapsedText: elapsedLabel(elapsed, phrase: phrase))
    }

    /// `m:ss` plus the span phrase. Minutes are not zero-padded, so paused and playing match (`0:54`, not `00:54`).
    /// `phrase` is `into the flyby` or `into the cab run`.
    static func elapsedLabel(_ elapsed: TimeInterval, phrase: String) -> String {
        let total = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60) + " " + phrase
    }

    static func elapsedPhrase(range: MissionRange) -> String {
        switch range {
        case .flyby: return "into the flyby"
        case .cab: return "into the cab run"
        }
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

/// Used for the whole unit-test host. It never calls ActivityKit, and nothing constructs an activity here.
@MainActor
final class SilentFlybyActivities: FlybyActivityClient {
    func identifiers() -> [String] { [] }
    func end(identifiers: [String]) async {}
    func request(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {}
    func update(_ state: FlybyActivityAttributes.ContentState, staleDate: Date?) async {}
}

enum FlybyLiveActivity {
    /// Ends and updates run one at a time. An end only dismisses the ids captured when it was scheduled.
    @MainActor
    private static var chain: Task<Void, Never>?

    /// Starts silent. The system client is installed only outside the unit-test host.
    @MainActor
    static var client: any FlybyActivityClient = SilentFlybyActivities()

    /// Builds the ActivityKit client. Tests replace this so the unit-test host never constructs one.
    @MainActor
    static var systemClientFactory: @MainActor () -> any FlybyActivityClient = {
        SystemFlybyActivities()
    }

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
        lastPushedAt = .distantPast
        lastPushedState = nil
        return previous
    }

    /// Ends a Live Activity left up by a previous launch.
    /// The shipping app and UI tests (`-ui-tests`) both do this. Playback services being off does not skip it.
    /// Only the unit-test host returns before ActivityKit is constructed.
    @MainActor
    static func endLeftoversAtLaunch(
        unitTestHost: Bool = RuntimeHost.isUnitTestHost,
        allowsPlayback: Bool = RuntimeHost.allowsPlaybackServices()
    ) {
        if unitTestHost {
            scheduleEndAllImmediately()
            return
        }
        endThroughSystemClient(keepInstalled: allowsPlayback)
    }

    /// Installs the ActivityKit client when playback may start, and always clears leftovers outside the unit-test host.
    /// UI tests keep the silent client after the clear, so Begin does not request a new activity.
    @MainActor
    static func useSystemClient(
        unitTestHost: Bool = RuntimeHost.isUnitTestHost,
        allowsPlayback: Bool = RuntimeHost.allowsPlaybackServices()
    ) {
        guard !unitTestHost else { return }
        if !allowsPlayback {
            endThroughSystemClient(keepInstalled: false)
            return
        }
        if !(client is SystemFlybyActivities) {
            client = systemClientFactory()
        }
        scheduleEndAllImmediately()
    }

    /// Reads the live activities from an ActivityKit client and ends those ids.
    /// `keepInstalled` leaves that client in place for later updates. Otherwise the silent client stays.
    @MainActor
    private static func endThroughSystemClient(keepInstalled: Bool) {
        let system: any FlybyActivityClient
        if keepInstalled, client is SystemFlybyActivities {
            system = client
        } else {
            system = systemClientFactory()
            if keepInstalled {
                client = system
            }
        }
        let ids = system.identifiers()
        enqueue {
            await system.end(identifiers: ids)
        }
    }

    /// Ends every activity visible on this turn, including one left up after a previous launch.
    /// The id list is taken before the first await, so an activity requested afterwards is left alone.
    @MainActor
    static func endAllImmediately() async {
        await scheduleEndAllImmediately().value
    }

    /// `-endActivitiesAndExit` together with `-ui-tests` asks a UI-test relaunch to dismiss every Live Activity and then quit.
    static func shouldEndActivitiesAndExit(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-ui-tests") && arguments.contains("-endActivitiesAndExit")
    }

    /// Ends every Live Activity and waits until that end has finished.
    /// UI tests (`-ui-tests`) are not the unit-test host, so this uses the ActivityKit client there.
    /// The unit-test host ends only the injected client and does not construct ActivityKit.
    @MainActor
    static func endAllForExit(unitTestHost: Bool = RuntimeHost.isUnitTestHost) async {
        if unitTestHost {
            await endAllImmediately()
            return
        }
        let system = systemClientFactory()
        if let reporting = system as? SystemFlybyActivities {
            reporting.logActivityCount()
        }
        let ids = system.identifiers()
        await system.end(identifiers: ids)
        await finishQueuedWork()
    }

    /// Waits until the end and update already queued on this turn have finished.
    @MainActor
    static func finishQueuedWork() async {
        await chain?.value
    }

    /// Registers the dismissal before returning. `sync` is queued behind it.
    /// The unit-test host's client is silent, so this does not touch ActivityKit there.
    @MainActor
    @discardableResult
    static func scheduleEndAllImmediately() -> Task<Void, Never> {
        let ending = client
        let ids = ending.identifiers()
        lastPushedState = nil
        return enqueue {
            await ending.end(identifiers: ids)
        }
    }

    /// Ceiling for ordinary pushes. Play, pause, a line or milestone change, and the span end pass `immediate` and skip this.
    @MainActor private static let minimumPushInterval: TimeInterval = 1
    @MainActor private static var lastPushedAt = Date.distantPast
    @MainActor private static var lastPushedState: FlybyActivityAttributes.ContentState?

    /// `immediate` is only for play/pause, a line or milestone change, and the span end.
    /// Everything else, including a frame decode after a memory warning, waits out `minimumPushInterval` and drops a repeat of the last state.
    @MainActor
    static func sync(
        arrived: Bool,
        playing: Bool,
        progress: Double,
        nextMilestone: String,
        speaker: String,
        clock: String,
        elapsedText: String,
        staleDate: Date?,
        immediate: Bool
    ) {
        enqueue {
            let state = FlybyActivityAttributes.ContentState(
                progress: progress,
                nextMilestone: nextMilestone,
                speaker: speaker,
                clock: clock,
                playing: playing,
                elapsedText: elapsedText
            )
            guard arrived else {
                let ids = client.identifiers()
                lastPushedState = nil
                await client.end(identifiers: ids)
                return
            }
            if client.identifiers().isEmpty {
                guard playing else { return }
                lastPushedAt = Date()
                lastPushedState = state
                await client.request(state, staleDate: staleDate)
                return
            }
            if lastPushedState == state { return }
            if !immediate, Date().timeIntervalSince(lastPushedAt) < minimumPushInterval { return }
            lastPushedAt = Date()
            lastPushedState = state
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
