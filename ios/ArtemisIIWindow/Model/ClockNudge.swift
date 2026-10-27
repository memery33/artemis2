import Foundation

/// VoiceOver increment and decrement on the mission scrubber.
/// This is a skip, not a scrub, so the clock is not frozen.
enum ClockNudge: Equatable {
    /// Lock-screen skip and the dock skips use this same interval.
    static let interval: TimeInterval = 15

    case back
    case forward

    var seconds: TimeInterval {
        switch self {
        case .back:
            return -Self.interval
        case .forward:
            return Self.interval
        }
    }

    /// The finger scrubber is not engaged.
    var scrubs: Bool { false }
}
