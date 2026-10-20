import SwiftUI

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
            TranscriptMarkup.matchesSearch(text: line.text, speaker: line.speaker, needle: needle)
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
                        Text(SpeakerLabel.heading(speaker: line.speaker, clock: "\(Stamp.clock(line.utc)) UTC"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TranscriptLineText(
                            text: line.text,
                            font: .body,
                            color: .primary,
                            annotationColor: .secondary
                        )
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
                        .font(HybridFont.display(22, relativeTo: .title3))
                    HStack(spacing: 16) {
                        Button(model.range == .flyby ? "Cab run" : "Flyby") {
                            if model.range == .flyby {
                                model.showCabRun()
                            } else {
                                model.showFlyby()
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("span-toggle")
                        Button(model.spatial ? "Spatial on" : "Spatial") {
                            model.setSpatial(!model.spatial)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("spatial-toggle")
                    }
                    .font(HybridFont.text(15, relativeTo: .subheadline))
                    .fontWeight(.semibold)
                    .buttonStyle(.plain)
                    if let attribution = model.timeline?.attribution {
                        Text(attribution.credit)
                            .font(HybridFont.text(17, relativeTo: .headline)).fontWeight(.semibold)
                    }
                    Text("This app is not affiliated with or endorsed by NASA.")
                        .font(HybridFont.text(17, relativeTo: .body))
                    Text("Now Playing lists “NASA/Artemis II Crew” as the artist. That is the credit for the crew recording, not a sign that NASA publishes this app.")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                    if let pointing = model.timeline?.pointing {
                        Text(pointing.note)
                            .font(HybridFont.text(13, relativeTo: .footnote))
                    }
                    Text("App icon cropped from art002e016184, a Z9 frame from inside the cabin, toward a window (NASA/Artemis II Crew).")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                    Text("Orion Window plays one clock: the crew recording, the Window 2 and Window 3 photographs, and a crater map of the track. The flyby and the cab run are separate spans. The span and spatial switches are on this screen.")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                    Text("The crater map, lroc-track.jpg, is a 1400 by 663 reprojection of the NASA SVS CGI Moon Kit 2025 LROC color map, SVS 4720, from 340° E to 150° E and 48° N to 42° S. The app draws it with north up and west on the left. Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio, Lunar Reconnaissance Orbiter Camera, Arizona State University, and Noah Petro (NASA/GSFC), visualization by Ernie Wright. It is an aesthetic rendering, not a photograph and not the flyby lighting.")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                    Text("Crater pages quote the Science and Operational Focus of NASA’s Guide to the Artemis II Lunar Targeting Plan for Aristarchus Plateau and Reiner Gamma. The pictures are the real frames already labeled with those targets.")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                    Text("Orion’s path is a JPL Horizons observer table: Moon (301) from Artemis II (spacecraft) -1024 body center, sub-observer east longitude and latitude in the IAU MOON_ME body-fixed frame, plus range, one-minute steps from 2026-04-06 18:00 UT through 2026-04-07 02:00 UT. MOON_ME +X is the 0° east meridian, not the body-equator node. Closest approach is the minimum of that table, not a typed-in time. Aristarchus and Reiner Gamma are labeled from the USGS Gazetteer of Planetary Nomenclature. Mare Orientale is an unlabeled dot at that mare’s USGS center.")
                        .font(HybridFont.text(13, relativeTo: .footnote))
                    if let licenses = model.timeline?.licenses {
                        ForEach(licenses) { license in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(license.bundle)
                                    .font(HybridFont.text(15, relativeTo: .subheadline)).fontWeight(.semibold)
                                if !license.doi.isEmpty {
                                    Text(license.doi)
                                        .font(HybridFont.text(12, relativeTo: .caption))
                                        .monospaced()
                                }
                                Text(license.credit)
                                    .font(HybridFont.text(12, relativeTo: .caption))
                                Text(license.usage)
                                    .font(HybridFont.text(13, relativeTo: .footnote))
                                if !license.shipped {
                                    Text("Not shipped in this app.")
                                        .font(HybridFont.text(12, relativeTo: .caption))
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    if let source = model.timeline?.missionStart {
                        Text("MET epoch \(source.utc). \(source.source)")
                            .font(HybridFont.text(13, relativeTo: .footnote))
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
