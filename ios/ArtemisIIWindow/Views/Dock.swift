import SwiftUI

struct DockBar: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var about = false
    @State private var transcript = false
    @State private var moments = false

    var body: some View {
        controls
            .sheet(isPresented: $about) { AboutView() }
            .sheet(isPresented: $transcript) { TranscriptSheet() }
            .sheet(isPresented: $moments) { MomentsSheet() }
    }

    @ViewBuilder
    private var controls: some View {
        capsuleControls
    }

    /// The same capsule on the Moon and in the cabin. Spatial, lines, and the spans are in the menu.
    private var capsuleControls: some View {
        HStack(spacing: 2) {
            capsuleSkip(
                system: "gobackward.15",
                label: "Skip back 15 seconds",
                identifier: "skip-back"
            ) {
                model.skip(by: -PlaybackModel.skipInterval)
            }
            capsulePlay
            capsuleSkip(
                system: "goforward.15",
                label: "Skip forward 15 seconds",
                identifier: "skip-forward"
            ) {
                model.skip(by: PlaybackModel.skipInterval)
            }
            capsuleText("Moments", label: "Moments", identifier: "moments-button") { moments = true }
            capsuleText("Info", label: "Info and Credits", identifier: "info-button") { about = true }
            moreMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transport-capsule")
    }

    private var capsulePlay: some View {
        let playing = model.playing
        return Button(action: { model.toggle() }) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 36)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playback-toggle")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    private func capsuleSkip(
        system: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    private func capsuleText(
        _ title: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(minHeight: 44)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }

    private var moreMenu: some View {
        Menu {
            Button(model.spatial ? "Spatial on" : "Spatial") {
                model.setSpatial(!model.spatial)
            }
            Button("Window 2") { model.setWindow(.nikon) }
            Button("Window 3") { model.setWindow(.cab) }
            Button("Lines") { transcript = true }
            Button(model.range == .flyby ? "Cab run" : "Flyby") {
                if model.range == .flyby { model.showCabRun() } else { model.showFlyby() }
            }
            Button("Crew, \(model.crewID)") { model.cycleCrew() }
            if model.immersed {
                Button("Back to the Moon") { model.surface() }
            } else {
                Button("Dive into the window") { model.dive() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("more-controls")
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
