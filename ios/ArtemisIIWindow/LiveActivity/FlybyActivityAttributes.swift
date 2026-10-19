import ActivityKit
import Foundation

struct FlybyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var progress: Double
        var nextMilestone: String
        var speaker: String
        var clock: String
    }

    var title: String
}
