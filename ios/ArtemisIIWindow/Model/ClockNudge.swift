import Foundation

/// VoiceOver increment and decrement on the mission scrubber.
/// This is a skip, not a scrub, so the clock is not frozen.
enum ClockNudge: Equatable {
    case back
    case forward

    var seconds: TimeInterval {
        switch self {
        case .back:
            return -PlaybackModel.skipInterval
        case .forward:
            return PlaybackModel.skipInterval
        }
    }

    /// The finger scrubber is not engaged.
    var scrubs: Bool { false }
}
