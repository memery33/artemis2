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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.setSceneActive(false)
            } else if phase == .active {
                model.setSceneActive(true)
            }
        }
    }
}

struct GateView: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var about = false

    var body: some View {
        ZStack {
            Button(action: { model.begin() }) {
                Text("Tap to begin")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tap to begin")

            VStack {
                Spacer()
                Button("About") { about = true }
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $about) {
            AboutView()
        }
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
        if model.phoneImages != phone {
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

/// Landscape phone. The glass fills the safe area; the island and home
/// indicator stay on the cabin. Controls sit in a side rail. Playback is
/// the same object as portrait, so rotation does not touch the clock.
struct LandscapeLayout: View {
    var body: some View {
        GeometryReader { geo in
            let rail = min(156, max(128, geo.size.width * 0.18))
            let inset: CGFloat = 6
            // The rail already scrolls. A fixed height is what makes that
            // scroll view clip, on a 375pt phone as well as a 402pt one.
            let railHeight = max(44, geo.size.height - inset * 2)
            HStack(alignment: .top, spacing: 8) {
                WindowPane(glassChrome: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DockBar(placement: .rail)
                    .frame(width: rail, height: railHeight)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, inset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

struct PhoneColumn: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClockReadout()
            WindowPane()
            FrameCaption(side: model.window)
            CreditLine()
            StatusLines()
            CabinCard(height: 96)
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
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ClockReadout()
                    WindowPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    FrameCaption(side: model.window)
                    CreditLine()
                    StatusLines()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        CompanionPane()
                        CabinCard(height: 72)
                        LiveTranscript()
                    }
                    .padding(.bottom, 12)
                }
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
