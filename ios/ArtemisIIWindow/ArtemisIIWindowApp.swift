import SwiftUI

@main
struct ArtemisIIWindowApp: App {
    @StateObject private var model: PlaybackModel

    init() {
        // A Live Activity from the previous process keeps the widget and chronod alive.
        // End it, and wait until that end finishes, before the player exists.
        // The unit-test host does not enter this path and does not touch ActivityKit.
        if !RuntimeHost.isUnitTestHost {
            FlybyLiveActivity.finishLaunchCleanup()
        }
        _model = StateObject(wrappedValue: PlaybackModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
        }
    }
}
