import SwiftUI
import UIKit

/// Haptic steps follow the Horizons range toward closest approach.
struct ApproachChrome: ViewModifier {
    @EnvironmentObject private var model: PlaybackModel
    @State private var lastStep = -1

    func body(content: Content) -> some View {
        content
            .onChange(of: model.utc) { _, date in
                respond(at: date)
            }
    }

    private func respond(at date: Date) {
        guard let bundled = FlybyEphemeris.bundled,
              let approach = FlybyPath.closestApproach(bundled.samples, radiusKm: bundled.document.radiusKm) else {
            return
        }
        let intensity = FlybyPath.approachIntensity(at: date, samples: bundled.samples, approach: approach)
        let step = Int(intensity * 5)
        if step > lastStep {
            lastStep = step
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred(intensity: CGFloat(min(1, max(0.15, intensity))))
        }
    }
}
