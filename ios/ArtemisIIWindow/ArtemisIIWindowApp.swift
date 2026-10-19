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
        }
    }
}
