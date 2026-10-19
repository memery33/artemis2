import SwiftUI

@main
struct ArtemisIIWindowApp: App {
    @StateObject private var model: PlaybackModel

    init() {
        // A Live Activity from the previous process keeps the widget and chronod alive.
        // End it before the player, the audio session, or anything else starts.
        FlybyLiveActivity.endAllImmediately()
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
