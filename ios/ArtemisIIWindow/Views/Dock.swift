import SwiftUI

enum DockPlacement {
    case bottom
    case rail
}

struct DockBar: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var about = false
    @State private var transcript = false
    @State private var moments = false
    var placement: DockPlacement = .bottom

    var body: some View {
        controls
            .sheet(isPresented: $about) { AboutView() }
            .sheet(isPresented: $transcript) { TranscriptSheet() }
            .sheet(isPresented: $moments) { MomentsSheet() }
    }

    @ViewBuilder
    private var controls: some View {
        switch placement {
        case .bottom:
            bottomControls
        case .rail:
            railControls
        }
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            timelineControls
            Toggle(isOn: Binding(
                get: { model.spatial },
                set: { model.setSpatial($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spatial")
                    Text("Moves the real recording toward this window. Nothing is added.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityIdentifier("spatial-note")
                }
            }
            .toggleStyle(.switch)
            .tint(.white)
            .font(.subheadline)
            .foregroundStyle(.white)
            .accessibilityIdentifier("spatial-toggle")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    windowButton(.nikon, title: "2", label: "Window 2")
                    windowButton(.cab, title: "3", label: "Window 3")
                    crewButton
                    linesButton
                    momentsButton
                    rangeButton
                    aboutButton
                }
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        windowButton(.nikon, title: "2", label: "Window 2")
                        windowButton(.cab, title: "3", label: "Window 3")
                        crewButton
                    }
                    HStack(spacing: 8) {
                        linesButton
                        momentsButton
                        rangeButton
                        aboutButton
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var railControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                timelineControls
                Toggle(isOn: Binding(
                    get: { model.spatial },
                    set: { model.setSpatial($0) }
                )) {
                    Text("Spatial")
                }
                .accessibilityHint("Moves the real recording toward this window. Nothing is added.")
                .accessibilityIdentifier("spatial-toggle")
                .toggleStyle(.switch)
                .tint(.white)
                .font(.subheadline)
                .foregroundStyle(.white)

                HStack(spacing: 8) {
                    windowButton(.nikon, title: "2", label: "Window 2")
                    windowButton(.cab, title: "3", label: "Window 3")
                }
                CrewRow()
                crewButton
                if model.immersed {
                    Button("Back to the Moon") { model.surface() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("surface-button")
                } else {
                    Button("Dive into the window") { model.dive() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("dive-button")
                }
                linesButton
                momentsButton
                rangeButton
                aboutButton
                CabinCard(height: 72)
                ExhibitCards()
                MoonGlobeView()
                    .frame(height: 168)
                TargetMap()
                    .frame(height: 120)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("landscape-rail")
    }

    /// Scrubber with the play control beside it. Skip uses the lock-screen interval.
    private var timelineControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    MissionScrubber()
                    playPauseButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    MissionScrubber()
                    playPauseButton
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                skipButton(
                    system: "gobackward.15",
                    title: "Back",
                    label: "Skip back 15 seconds",
                    identifier: "skip-back"
                ) {
                    model.skip(by: -PlaybackModel.skipInterval)
                }
                skipButton(
                    system: "goforward.15",
                    title: "Forward",
                    label: "Skip forward 15 seconds",
                    identifier: "skip-forward"
                ) {
                    model.skip(by: PlaybackModel.skipInterval)
                }
            }
        }
    }

    private var playPauseButton: some View {
        let playing = model.playing
        return Button(action: { model.toggle() }) {
            Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(minWidth: 112, minHeight: 48)
                .padding(.horizontal, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playback-toggle")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    private func skipButton(
        system: String,
        title: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: system)
                    .font(.title2)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(minWidth: 64, minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    private var crewButton: some View {
        dockButton(model.crewID, label: "Crew, \(model.crewID)") {
            model.cycleCrew()
        }
    }

    private var linesButton: some View {
        dockButton("Lines", label: "Transcript") { transcript = true }
    }

    private var momentsButton: some View {
        dockButton("Moments", label: "Moments") { moments = true }
            .accessibilityIdentifier("moments-button")
    }

    private var rangeButton: some View {
        dockButton(
            model.range == .flyby ? "Cab run" : "Flyby",
            label: model.range == .flyby ? "Cab Cam run" : "Flyby window"
        ) {
            if model.range == .flyby { model.showCabRun() } else { model.showFlyby() }
        }
    }

    private var aboutButton: some View {
        dockButton("About", label: "About") { about = true }
    }

    private func windowButton(_ side: WindowSide, title: String, label: String) -> some View {
        dockButton(title, label: label, selected: model.window == side) {
            model.setWindow(side)
        }
    }

    private func dockButton(
        _ title: String,
        label: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: placement == .rail ? .infinity : nil)
                .padding(.horizontal, 8)
                .background(selected ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct LiveTranscript: View {
    @EnvironmentObject private var model: PlaybackModel

    private var rows: [TranscriptLine] {
        let lines = model.timeline?.lines.filter { $0.track == model.trackID } ?? []
        return lines.filter { line in
            let delta = line.date.timeIntervalSince(model.utc)
            return delta > -15 && delta < 45
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            if rows.isEmpty {
                Text("No transcript line in this stretch.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ForEach(rows) { line in
                    Button(action: { model.seek(toLine: line) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(line.speaker) · \(Stamp.clock(line.utc))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(line.text)
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TranscriptSheet: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var allTracks = false

    private var rows: [TranscriptLine] {
        let source = model.timeline?.lines ?? []
        let tracked = allTracks ? source : source.filter { $0.track == model.trackID }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return tracked }
        return tracked.filter { line in
            line.text.localizedCaseInsensitiveContains(needle)
                || line.speaker.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List(rows) { line in
                Button(action: {
                    model.seek(toLine: line)
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(line.speaker) · \(Stamp.clock(line.utc)) UTC")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(line.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Search the transcript")
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allTracks ? "This track" : "All tracks") {
                        allTracks.toggle()
                    }
                }
            }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Orion Window: Artemis II Flyby")
                        .font(.title3.weight(.semibold))
                    if let attribution = model.timeline?.attribution {
                        Text(attribution.credit)
                            .font(.headline)
                        Text(attribution.endorsement)
                            .font(.body)
                    }
                    Text("This app is not affiliated with or endorsed by NASA.")
                        .font(.body)
                    Text("Now Playing lists “NASA/Artemis II Crew” as the artist. That is the credit for the crew recording, not a sign that NASA publishes this app.")
                        .font(.footnote)
                    if let pointing = model.timeline?.pointing {
                        Text(pointing.note)
                            .font(.footnote)
                    }
                    Text("The app icon is a center crop of NASA ID art002e016184, a real Z9 frame from 19:33:26 UTC. It is not a new photograph.")
                        .font(.footnote)
                    Text("The globe uses the NASA SVS CGI Moon Kit 2025 LROC color map, file lroc_color_2k.jpg, 2048 by 1024, public domain. Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio, Lunar Reconnaissance Orbiter Camera, visualization by Ernie Wright. SVS 4720. The map is centered on 0° longitude and is an aesthetic rendering, not a photograph and not the flyby lighting.")
                        .font(.footnote)
                    Text("Exhibit cards quote the Focus column of NASA’s Guide to the Artemis II Lunar Targeting Plan for Aristarchus Plateau, Reiner Gamma, and Orientale Basin. The pictures are the real frames already labeled with those targets.")
                        .font(.footnote)
                    Text("Orion’s path is a JPL Horizons geometric state table: target Artemis II (spacecraft) -1024, center Moon (301) body center, MEAN_ME body equator, east-longitude positive, one-minute steps from 2026-04-06 18:00 UT through 2026-04-07 02:00 UT. Closest approach is the minimum of that table, not a typed-in time. Surface labels use the USGS Gazetteer of Planetary Nomenclature: Aristarchus, Reiner Gamma, and Mare Orientale.")
                        .font(.footnote)
                    if let licenses = model.timeline?.licenses {
                        ForEach(licenses) { license in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(license.bundle)
                                    .font(.subheadline.weight(.semibold))
                                if !license.doi.isEmpty {
                                    Text(license.doi)
                                        .font(.caption.monospaced())
                                }
                                Text(license.credit)
                                    .font(.caption)
                                Text(license.usage)
                                    .font(.footnote)
                                if !license.shipped {
                                    Text("Not shipped in this app.")
                                        .font(.caption)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    if let source = model.timeline?.missionStart {
                        Text("MET epoch \(source.utc). \(source.source)")
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Orion Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
