import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.loadError != nil {
                Text(model.loadError ?? "Timeline was not copied into the app.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(24)
            } else if model.arrived {
                StageView()
            } else {
                GateView()
            }
            if model.arrived, model.ended {
                EndCard()
                    .transition(.identity)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            }
        }
        .onAppear {
            if scenePhase == .active {
                RuntimeHost.noteSceneBecameActive()
                model.setSceneActive(true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Backgrounding never ends the Live Activity. setSceneActive pushes
                // the current state, including a pause, before the scene suspends.
                model.setSceneActive(false)
            } else if phase == .active {
                RuntimeHost.noteSceneBecameActive()
                model.setSceneActive(true)
            }
        }
    }
}

struct GateView: View {
    @EnvironmentObject private var model: PlaybackModel

    /// Cab Cam 2 at 22:36:03. The Moon sits on the right of this wide frame.
    private var hero: Frame? {
        model.timeline?.frames.first { $0.nasaID == "art002e041348" }
    }

    private var title: String {
        let label = model.timeline?.window.label ?? ""
        if label == "Aristarchus Plateau to Reiner Gamma" {
            return "Aristarchus\nPlateau to\nReiner Gamma"
        }
        return label
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HybridColor.ground.ignoresSafeArea()
            if let hero, let image = model.photo(hero, maxPixel: 1400) {
                PlacedPhoto(image: image, objectX: 0.34, objectY: 0.42)
                    .ignoresSafeArea()
                    .accessibilityLabel(FrameSelection.photoAccessLabel(hero))
                    .accessibilityAddTraits(.isImage)
                PlacedPhoto(image: image, objectX: 0.34, objectY: 0.42)
                    .blur(radius: 28)
                    .opacity(0.32)
                    .blendMode(.screen)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            RadialGradient(
                colors: [.clear, .black.opacity(0.55)],
                center: UnitPoint(x: 0.62, y: 0.32),
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                Text("ORION WINDOW")
                    .font(HybridFont.text(11, relativeTo: .caption2))
                    .tracking(1.8)
                    .foregroundStyle(HybridColor.gold)
                Text(title)
                    .font(HybridFont.display(48, relativeTo: .largeTitle))
                    .foregroundStyle(HybridColor.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 4)
                if let hero {
                    Text("\(hero.nasaID) · \(Stamp.clock(hero.utc)) UTC")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                        .foregroundStyle(HybridColor.dim)
                        .padding(.top, 12)
                    Text(hero.cameraLabel)
                        .font(HybridFont.text(13, relativeTo: .footnote))
                        .foregroundStyle(HybridColor.dim)
                }
                CreditLine()
                    .padding(.top, 4)
                Button(action: { model.begin() }) {
                    Text("Begin Flyby")
                        .font(HybridFont.text(17, relativeTo: .body))
                        .fontWeight(.semibold)
                        .foregroundStyle(HybridColor.ink)
                        .frame(minWidth: 180, minHeight: 50)
                        .padding(.horizontal, 22)
                        .background(HybridColor.cream, in: Capsule())
                        .shadow(color: .black.opacity(0.38), radius: 16, y: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Begin Flyby")
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: 360, alignment: .leading)
        }
        .preferredColorScheme(.dark)
        .task(id: hero?.nasaID) {
            guard let hero else { return }
            RuntimeHost.noteSceneBecameActive()
            for _ in 0..<40 {
                if Task.isCancelled { return }
                model.prefetch(hero, maxPixel: 1400)
                if model.photo(hero, maxPixel: 1400) != nil { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}

struct EndCard: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("End of this span")
                    .font(HybridFont.display(34, relativeTo: .largeTitle))
                    .foregroundStyle(HybridColor.cream)
                if let span = model.activeSpan {
                    Text("\(span.label) ends at \(Stamp.clock(span.endUTC)) UTC.")
                        .font(HybridFont.text(20, relativeTo: .title3))
                        .foregroundStyle(HybridColor.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Credit: NASA/Artemis II Crew")
                    .font(HybridFont.text(12, relativeTo: .caption))
                    .foregroundStyle(HybridColor.cream.opacity(0.8))
                Button("Replay this span") {
                    if let span = model.activeSpan {
                        model.seek(to: span.start)
                        model.play()
                    }
                }
                .font(HybridFont.text(17, relativeTo: .body))
                .fontWeight(.semibold)
                .foregroundStyle(HybridColor.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Color.white, in: Capsule())
                Button("Stay with the recording") {
                    model.ended = false
                }
                .font(HybridFont.text(17, relativeTo: .body))
                .foregroundStyle(HybridColor.cream)
                .frame(minHeight: 44)
            }
            .padding(28)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("end-card")
    }
}

struct StageView: View {
    var body: some View {
        HybridStage()
    }
}
