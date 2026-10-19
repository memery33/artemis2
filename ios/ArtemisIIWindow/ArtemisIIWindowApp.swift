import SwiftUI

@main
struct ArtemisIIWindowApp: App {
    @StateObject private var model: PlaybackModel

    init() {
        // A Live Activity from the previous process keeps the widget and chronod alive.
        // Register the dismissal before the player exists. sync is queued behind it and cannot request until the dismissal finishes.
        FlybyLiveActivity.scheduleEndAllImmediately()
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
