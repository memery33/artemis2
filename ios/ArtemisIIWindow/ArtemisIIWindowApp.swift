import SwiftUI

@main
struct ArtemisIIWindowApp: App {
    @StateObject private var model: PlaybackModel

    init() {
        // End a Live Activity left up by a previous launch before the player exists.
        // The unit-test host does not construct an ActivityKit client here.
        FlybyLiveActivity.endLeftoversAtLaunch()
        _model = StateObject(wrappedValue: PlaybackModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
                .task {
                    guard FlybyLiveActivity.shouldEndActivitiesAndExit() else { return }
                    // Reach idle before ending, so a UI-test launch can observe this process.
                    try? await Task.sleep(for: .milliseconds(500))
                    await FlybyLiveActivity.endAllForExit()
                    guard !RuntimeHost.isUnitTestHost else { return }
                    exit(0)
                }
        }
    }
}
