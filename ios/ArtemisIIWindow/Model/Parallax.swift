import Foundation

/// Point offsets from device tilt. Photo and frame limits are separate and clamped.
struct ParallaxShift: Equatable, Sendable {
    var photoX: Double
    var photoY: Double
    var frameX: Double
    var frameY: Double

    static let zero = ParallaxShift(photoX: 0, photoY: 0, frameX: 0, frameY: 0)
    static let photoLimit = 18.0
    static let frameLimit = 6.0

    static func clamp(_ value: Double, limit: Double) -> Double {
        min(limit, max(-limit, value))
    }

    /// `pitch` and `roll` are radians. Reduce Motion passes `enabled: false` and gets zero.
    static func shift(pitch: Double, roll: Double, enabled: Bool) -> ParallaxShift {
        guard enabled else { return .zero }
        return ParallaxShift(
            photoX: clamp(roll * 36, limit: photoLimit),
            photoY: clamp(pitch * 36, limit: photoLimit),
            frameX: clamp(roll * 12, limit: frameLimit),
            frameY: clamp(pitch * 12, limit: frameLimit)
        )
    }
}
