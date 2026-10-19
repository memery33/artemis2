import CoreMotion
import SwiftUI
import UIKit

@MainActor
final class CabinMotion: ObservableObject {
    @Published var shift = ParallaxShift.zero
    private let manager: CMMotionManager? = RuntimeHost.isUnitTestHost ? nil : CMMotionManager()

    func update(reduceMotion: Bool) {
        guard let manager else {
            shift = .zero
            return
        }
        if reduceMotion || !manager.isDeviceMotionAvailable {
            manager.stopDeviceMotionUpdates()
            shift = .zero
            return
        }
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let next = ParallaxShift.shift(
                pitch: motion.attitude.pitch,
                roll: motion.attitude.roll,
                enabled: true
            )
            Task { @MainActor in
                self?.shift = next
            }
        }
    }

    func stop() {
        manager?.stopDeviceMotionUpdates()
    }
}

/// Haptic steps follow the Horizons range toward closest approach.
/// The chrome fades for three seconds only when the clock is at that instant.
struct ApproachChrome: ViewModifier {
    @EnvironmentObject private var model: PlaybackModel
    @State private var hidden = false
    @State private var lastStep = -1
    @State private var fadeID = 0

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .onChange(of: model.utc) { _, date in
                respond(at: date)
            }
    }

    private func respond(at date: Date) {
        guard let bundled = FlybyEphemeris.bundled,
              let approach = FlybyPath.closestApproach(bundled.samples, radiusKm: bundled.document.radiusKm) else {
            return
        }
        let samples = bundled.samples
        let intensity = FlybyPath.approachIntensity(at: date, samples: samples, approach: approach)
        let step = Int(intensity * 5)
        if step > lastStep {
            lastStep = step
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred(intensity: CGFloat(min(1, max(0.15, intensity))))
        }
        guard FlybyPath.fadesInterface(at: date, approach: approach.date), !hidden else { return }
        hidden = true
        fadeID += 1
        let token = fadeID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if token == fadeID {
                hidden = false
            }
        }
    }
}
