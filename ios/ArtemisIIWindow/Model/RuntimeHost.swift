import Foundation

/// The unit-test host is this app process. UI tests launch the app on their own
/// and do not set `XCTestConfigurationFilePath`, so the globe still runs there.
enum RuntimeHost {
    /// Written on the main thread when the first scene becomes active.
    private nonisolated(unsafe) static var sceneActive = false

    static var isUnitTestHost: Bool {
        let process = ProcessInfo.processInfo
        if process.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return process.arguments.contains("-XCTest")
            || process.arguments.contains("-unit-tests")
    }

    /// Moon-map and cabin-frame decode stay off until a scene is active, and never run in the unit-test host.
    static var mayDecodeImages: Bool {
        sceneActive && !isUnitTestHost
    }

    static func noteSceneBecameActive() {
        sceneActive = true
    }
}
