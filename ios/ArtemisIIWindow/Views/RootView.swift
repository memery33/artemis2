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
    @State private var screen = CGSize.zero

    private var fold: Bool {
        LayoutChoice.isOpenFold(
            width: Double(screen.width),
            height: Double(screen.height),
            regularWidth: horizontalSizeClass == .regular
        )
    }

    var body: some View {
        Group {
            if fold {
                FoldLayout()
            } else {
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
        .onAppear { model.phoneImages = !fold }
        .onChange(of: fold) { _, isFold in
            model.phoneImages = !isFold
        }
    }
}

struct PhoneLayout: View {
    var body: some View {
        ViewThatFits(in: .vertical) {
            PhoneColumn()
            ScrollView {
                PhoneColumn()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DockBar()
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
