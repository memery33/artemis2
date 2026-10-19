import ActivityKit
import Foundation

extension FlybyActivityAttributes: ActivityAttributes {}

/// The only type in the app that calls ActivityKit. Playback installs it outside the unit-test host. Tests never construct it.
@MainActor
final class SystemFlybyActivities: FlybyActivityClient {
    func identifiers() -> [String] {
        Activity<FlybyActivityAttributes>.activities.map(\.id)
    }

    /// Printed by the UI-test tearDown relaunch before those activities are ended.
    func logActivityCount() {
        print("Activity.activities.count = \(Activity<FlybyActivityAttributes>.activities.count)")
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
