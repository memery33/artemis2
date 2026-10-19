import XCTest

/// UI tests pass `-ui-tests` so the app does not start a Live Activity or the audio session.
@MainActor
enum FlybyUILaunch {
    static func application(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-tests"] + extraArguments
        return app
    }

    /// Stops the app, then relaunches it so it ends every Live Activity and quits.
    /// A playback UI test can leave the widget extension running; the next unit-test process then hangs.
    static func endActivities() {
        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app.launchArguments = ["-ui-tests", "-endActivitiesAndExit"]
        // The app logs Activity.activities.count, then ends those activities and exits.
        app.launch()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue),
            object: app
        )
        _ = XCTWaiter.wait(for: [gone], timeout: 15)
        if app.state != .notRunning {
            app.terminate()
        }
    }
}
