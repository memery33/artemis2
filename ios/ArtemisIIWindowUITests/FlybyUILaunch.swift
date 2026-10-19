import XCTest

/// UI tests pass `-ui-tests` so the app does not start a Live Activity or the audio session.
@MainActor
enum FlybyUILaunch {
    static func application(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-tests"] + extraArguments
        return app
    }
}
