import SwiftUI

@main
struct ArtemisIIWindowApp: App {
    @StateObject private var model = PlaybackModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
        }
    }
}
