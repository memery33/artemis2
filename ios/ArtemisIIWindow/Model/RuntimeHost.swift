import Foundation

/// The unit-test host is this app process. UI tests launch the app on their own
/// and do not set `XCTestConfigurationFilePath`, so the globe still runs there.
enum RuntimeHost {
    static var isUnitTestHost: Bool {
        let process = ProcessInfo.processInfo
        if process.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return process.arguments.contains("-XCTest")
            || process.arguments.contains("-unit-tests")
    }
}
