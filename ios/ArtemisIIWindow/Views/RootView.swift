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
                model.setSceneActive(false)
                // Keep the Live Activity while audio is playing in the background.
                // End it only when the scene backgrounds with playback already paused.
                if !model.playing {
                    FlybyLiveActivity.scheduleEndAllImmediately()
                }
            } else if phase == .active {
                RuntimeHost.noteSceneBecameActive()
                model.setSceneActive(true)
            }
        }
    }
}

struct GateView: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var about = false

    private var hero: Frame? {
        model.timeline?.frames.first { $0.nasaID == "art002e009951" }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                if let hero {
                    VStack(spacing: 8) {
                        // art002e009951 is a bright limb. The black sky sits on the right,
                        // so the square keeps the lit surface. The frame stays up while the
                        // JPEG decodes, and the credit stays under it.
                        Color.clear
                            .frame(width: 220, height: 220)
                            .overlay(alignment: .leading) {
                                if let image = model.photo(hero, maxPixel: 900) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 320, height: 220)
                                }
                            }
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .accessibilityLabel(FrameSelection.photoAccessLabel(hero))
                        CreditLine()
                    }
                }
                VStack(spacing: 6) {
                    Text("Orion Window")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Artemis II Flyby")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Button(action: { model.begin() }) {
                    Text("Begin Flyby")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 200, minHeight: 52)
                        .padding(.horizontal, 18)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Begin Flyby")
                Button("About") { about = true }
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(28)
        }
        .task(id: hero?.nasaID) {
            guard let hero else { return }
            RuntimeHost.noteSceneBecameActive()
            for _ in 0..<40 {
                if Task.isCancelled { return }
                model.prefetch(hero, maxPixel: 900)
                if model.photo(hero, maxPixel: 900) != nil { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        .sheet(isPresented: $about) {
            AboutView()
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
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
                if let span = model.activeSpan {
                    Text("\(span.label) ends at \(Stamp.clock(span.endUTC)) UTC.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Credit: NASA/Artemis II Crew")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Replay this span") {
                    if let span = model.activeSpan {
                        model.seek(to: span.start)
                        model.play()
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Color.white, in: Capsule())
                Button("Stay with the recording") {
                    model.ended = false
                }
                .font(.body)
                .foregroundStyle(.white)
                .frame(minHeight: 44)
            }
            .padding(28)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("end-card")
    }
}

private struct ScreenSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

struct StageView: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var screen = CGSize.zero

    private var mode: StageMode {
        LayoutChoice.stage(
            width: Double(screen.width),
            height: Double(screen.height),
            regularWidth: horizontalSizeClass == .regular,
            compactHeight: verticalSizeClass == .compact
        )
    }

    var body: some View {
        Group {
            switch mode {
            case .fold:
                FoldLayout()
            case .landscape:
                LandscapeLayout()
            case .phone:
                PhoneLayout()
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ScreenSizeKey.self, value: geo.size)
            }
            .ignoresSafeArea()
        }
        .modifier(ApproachChrome())
        .onPreferenceChange(ScreenSizeKey.self) { screen = $0 }
        .onAppear { applyFrameTier() }
        .onChange(of: mode) { _, _ in
            applyFrameTier()
        }
    }

    /// Only the open fold changes the frame tier. Turning a phone sideways
    /// does not seek, pause, or rebuild the player.
    private func applyFrameTier() {
        let phone = LayoutChoice.readsPhoneFrames(mode)
        let model = model
        guard model.phoneImages != phone else { return }
        // The size preference can change mode during the view update. Publish on the next turn.
        Task { @MainActor in
            guard model.phoneImages != phone else { return }
            model.phoneImages = phone
        }
    }
}

struct PhoneLayout: View {
    var body: some View {
        // The column ends where the dock starts. A safe-area inset would
        // leave this scroll view full height, so the caption draws through
        // the dock at the default offset.
        VStack(spacing: 0) {
            ScrollView {
                PhoneColumn()
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("phone-column")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            DockBar()
        }
    }
}

/// Landscape phone. The Moon fills the left side. Crew, credit, and exhibits
/// sit on the right, and the capsule runs along the bottom. Playback is the
/// same object as portrait, so rotation does not touch the clock.
struct LandscapeLayout: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var exhibits = false

    var body: some View {
        GeometryReader { geo in
            if model.immersed {
                cabin(in: geo.size)
            } else {
                globe(in: geo.size)
            }
        }
        .sheet(isPresented: $exhibits) {
            NavigationStack {
                ScrollView {
                    ExhibitCards()
                        .padding(16)
                }
                .background(Color.black)
                .navigationTitle("Exhibits")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { exhibits = false }
                    }
                }
            }
        }
    }

    /// Globe on the left, crew and credit on the right, capsule along the bottom.
    private func globe(in size: CGSize) -> some View {
        let panel = min(320, max(220, size.width * 0.38))
        return VStack(spacing: 0) {
            ClockReadout()
                .padding(.horizontal, 12)
                .padding(.top, 4)
            HStack(alignment: .top, spacing: 8) {
                MoonGlobeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, 8)
                VStack(alignment: .leading, spacing: 8) {
                    CrewRow()
                    CreditLine()
                    Button("Exhibits") { exhibits = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("exhibits-button")
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 10)
                .padding(.top, 4)
                .frame(width: panel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            DockBar()
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func cabin(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            WindowPane(glassChrome: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
            DockBar()
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

struct PhoneColumn: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClockReadout()
            if model.immersed {
                WindowPane()
                Button("Back to the Moon") { model.surface() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("surface-button")
            } else {
                MoonGlobeView()
                    .frame(height: 320)
                Button("Dive into the window") { model.dive() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("dive-button")
            }
            CrewRow()
            FrameCaption(side: model.window)
            StatusLines()
            CabinCard(height: 96)
            // The other-window thumbnail lives in the fold's narrow column. Here it would span the phone.
            ExhibitCards()
            TargetMap()
                .frame(height: 180)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

struct FoldLayout: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ClockReadout()
                    WindowPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    FrameCaption(side: model.window)
                    StatusLines()
                }
                .padding(.trailing, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        MoonGlobeView()
                            .frame(height: 280)
                        CrewRow()
                        LyricLines(focus: LyricFocus.focus(
                            at: model.utc,
                            track: model.trackID,
                            lines: model.timeline?.lines ?? []
                        ))
                        ExhibitCards()
                        CompanionPane()
                        CabinCard(height: 72)
                        LiveTranscript()
                    }
                    .padding(.bottom, 12)
                }
                .padding(.leading, 30)
                .frame(width: min(340, geo.size.width * 0.38))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DockBar()
        }
    }
}
