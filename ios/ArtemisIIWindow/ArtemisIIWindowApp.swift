import SwiftUI

@main
struct ArtemisIIWindowApp: App {
    @StateObject private var model: PlaybackModel

    init() {
        // The unit-test host must not construct an ActivityKit client. Playback installs one later, and only outside tests.
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
