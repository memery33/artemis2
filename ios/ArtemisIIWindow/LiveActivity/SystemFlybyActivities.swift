import ActivityKit
import Foundation
import os

extension FlybyActivityAttributes: ActivityAttributes {}

private let liveActivityLog = Logger(subsystem: "com.memery33.artemis2window", category: "LiveActivity")

/// The only type in the app that calls ActivityKit. Playback installs it outside the unit-test host. Tests never construct it.
@MainActor
final class SystemFlybyActivities: FlybyActivityClient {
    func identifiers() -> [String] {
        Activity<FlybyActivityAttributes>.activities.map(\.id)
    }

    /// Logged by the UI-test tearDown relaunch before those activities are ended.
    func logActivityCount() {
        let count = Activity<FlybyActivityAttributes>.activities.count
        liveActivityLog.log("Activity.activities.count = \(count, privacy: .public)")
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
