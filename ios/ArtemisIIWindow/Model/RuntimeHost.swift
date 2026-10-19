import Foundation

/// The unit-test host is this app process. UI tests launch the app on their own
/// and do not set `XCTestConfigurationFilePath`, so the globe still runs there.
enum RuntimeHost {
    /// Written when the first scene becomes active. Main-actor isolated, so readers do not need a lock.
    @MainActor
    private static var sceneActive = false

    static var isUnitTestHost: Bool {
        let process = ProcessInfo.processInfo
        if process.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return process.arguments.contains("-XCTest")
            || process.arguments.contains("-unit-tests")
    }

    /// Moon-map and cabin-frame decode stay off until a scene is active, and never run in the unit-test host.
    @MainActor
    static var mayDecodeImages: Bool {
        sceneActive && !isUnitTestHost
    }

    @MainActor
    static func noteSceneBecameActive() {
        sceneActive = true
    }

    /// Live Activities and the spoken audio session stay off for the unit-test host and for UI tests.
    /// A test opts in with `-allow-playback-session`.
    static func allowsPlaybackServices(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        unitTestHost: Bool = isUnitTestHost
    ) -> Bool {
        if arguments.contains("-allow-playback-session") { return true }
        if unitTestHost { return false }
        if arguments.contains("-ui-tests") { return false }
        return true
    }
}
