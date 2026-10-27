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
        pending = nil
        armedFlushDelay = nil
        flushTask?.cancel()
        flushTask = nil
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
        pending = nil
        flushTask?.cancel()
        flushTask = nil
        return enqueue {
            pending = nil
            flushTask?.cancel()
            flushTask = nil
            lastPushedState = nil
            await ending.end(identifiers: ids)
        }
    }

    /// Ceiling for ordinary pushes. Play, pause, a line or milestone change, the span end,
    /// and a seek, skip, or other user-requested push pass `immediate` and skip this.
    /// A non-immediate update inside the window is kept and sent when the window ends.
    @MainActor private static let minimumPushInterval: TimeInterval = 1
    @MainActor private static var lastPushedAt = Date.distantPast
    @MainActor private static var lastPushedState: FlybyActivityAttributes.ContentState?
    @MainActor private static var pending: DeferredActivity?
    @MainActor private static var flushTask: Task<Void, Never>?
    /// Delay of the latest flush arm. Tests read it. Shipping code still sleeps that long.
    @MainActor static var armedFlushDelay: TimeInterval?

    /// Latest update that arrived inside `minimumPushInterval` and was not immediate.
    /// Flushed once that window has elapsed, including while playback is paused.
    private struct DeferredActivity {
        var state: FlybyActivityAttributes.ContentState
        var staleDate: Date?
        var now: @MainActor () -> Date
        var onSent: (@MainActor () -> Void)?
    }

    /// `immediate` is play/pause, a line or milestone change, the span end, and a user-requested push.
    /// An identical state is dropped. Anything else inside `minimumPushInterval` replaces `pending`
    /// and is sent after the window, so the latest state still lands while paused.
    /// `now` is the caller's clock, captured here so a test can move time without waiting.
    /// `onSent` runs only after a request or update is actually handed to the client.
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
        immediate: Bool,
        now: @escaping @MainActor () -> Date = { Date() },
        onSent: (@MainActor () -> Void)? = nil
    ) {
        let stamp = now()
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
                pending = nil
                flushTask?.cancel()
                flushTask = nil
                lastPushedState = nil
                await client.end(identifiers: ids)
                return
            }
            if client.identifiers().isEmpty {
                pending = nil
                flushTask?.cancel()
                flushTask = nil
                guard playing else { return }
                await publish(state, staleDate: staleDate, playing: playing, stamp: stamp, onSent: onSent)
                return
            }
            if lastPushedState == state {
                pending = nil
                flushTask?.cancel()
                flushTask = nil
                return
            }
            let elapsed = stamp.timeIntervalSince(lastPushedAt)
            if !immediate, elapsed < minimumPushInterval {
                pending = DeferredActivity(state: state, staleDate: staleDate, now: now, onSent: onSent)
                armFlush(after: minimumPushInterval - elapsed)
                return
            }
            pending = nil
            flushTask?.cancel()
            flushTask = nil
            await publish(state, staleDate: staleDate, playing: playing, stamp: stamp, onSent: onSent)
        }
    }

    /// Sends the deferred update once `now` is past the 1 s window. Tests call this after moving the clock.
    /// The unit-test host does not sleep; shipping code arms that sleep from `sync`.
    @MainActor
    static func flushPending() async {
        await enqueue {
            await deliverPending()
        }.value
    }

    @MainActor
    private static func armFlush(after delay: TimeInterval) {
        armedFlushDelay = delay
        guard !RuntimeHost.isUnitTestHost else { return }
        flushTask?.cancel()
        let nanos = UInt64(max(0.0, delay) * 1_000_000_000)
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            enqueue {
                await deliverPending()
            }
        }
    }

    @MainActor
    private static func deliverPending() async {
        guard let waiting = pending else { return }
        let stamp = waiting.now()
        let elapsed = stamp.timeIntervalSince(lastPushedAt)
        guard elapsed >= minimumPushInterval else {
            armFlush(after: minimumPushInterval - elapsed)
            return
        }
        pending = nil
        flushTask?.cancel()
        flushTask = nil
        guard waiting.state != lastPushedState else { return }
        await publish(
            waiting.state,
            staleDate: waiting.staleDate,
            playing: waiting.state.playing,
            stamp: stamp,
            onSent: waiting.onSent
        )
    }

    @MainActor
    private static func publish(
        _ state: FlybyActivityAttributes.ContentState,
        staleDate: Date?,
        playing: Bool,
        stamp: Date,
        onSent: (@MainActor () -> Void)?
    ) async {
        if client.identifiers().isEmpty {
            guard playing else { return }
            lastPushedAt = stamp
            lastPushedState = state
            await client.request(state, staleDate: staleDate)
            onSent?()
            return
        }
        lastPushedAt = stamp
        lastPushedState = state
        await client.update(state, staleDate: staleDate)
        onSent?()
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
