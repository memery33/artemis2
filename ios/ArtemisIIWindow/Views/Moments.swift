import SwiftUI

struct MissionScrubber: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var dragging = false
    @State private var dragFraction = 0.0
    /// A slider set can arrive before `onEditingChanged`. It is not a scrub until then.
    @State private var armed = false
    @State private var cachedMarks = SpanCoverage(audio: [], silent: [], photos: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            coverage
                .frame(height: 14)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { dragging ? dragFraction : fraction },
                    set: { newValue in
                        dragFraction = newValue
                        if dragging {
                            model.scrub(toFraction: newValue)
                        } else {
                            armed = true
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        if !armed {
                            dragFraction = fraction
                        }
                        armed = false
                        dragging = true
                        model.beginScrub()
                        model.scrub(toFraction: dragFraction)
                    } else {
                        armed = false
                        dragging = false
                        model.endScrub()
                    }
                }
            )
            .tint(.white)
            .accessibilityLabel("Mission clock")
            .accessibilityValue(ClockMath.utcText(model.utc))
            .accessibilityIdentifier("mission-scrubber")
            .accessibilityAdjustableAction { direction in
                armed = false
                model.accessibilityAdjust(direction)
            }
            Text("Bar: audio. Ticks: photos. Empty: silence.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: coverageKey, initial: true) { _, _ in
            cachedMarks = loadedCoverage()
        }
    }

    private var fraction: Double {
        guard let span = model.activeSpan else { return 0 }
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else { return 0 }
        return min(1, max(0, model.utc.timeIntervalSince(span.start) / duration))
    }

    private var coverage: some View {
        GeometryReader { geo in
            let marks = cachedMarks
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                ForEach(marks.audio) { row in
                    Capsule()
                        .fill(Color.white.opacity(0.72))
                        .frame(width: max(1, band(row, width: width).width), height: 6)
                        .offset(x: band(row, width: width).x)
                }
                ForEach(Array(marks.photos.enumerated()), id: \.offset) { _, date in
                    Rectangle()
                        .fill(Color(red: 0.84, green: 0.69, blue: 0.37))
                        .frame(width: 2, height: 12)
                        .offset(x: position(date, width: width))
                }
            }
        }
    }

    private var coverageKey: String {
        let version = model.timeline.map { String($0.version) } ?? "none"
        return "\(version)|\(model.range)|\(model.trackID)|\(model.window)"
    }

    private func loadedCoverage() -> SpanCoverage {
        guard let timeline = model.timeline else {
            return SpanCoverage(audio: [], silent: [], photos: [])
        }
        return MilestoneList.coverage(
            timeline: timeline,
            range: model.range,
            track: model.trackID,
            window: model.window
        )
    }

    private func band(_ row: SpanCoverage.Interval, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        guard let span = model.activeSpan else { return (0, 0) }
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else { return (0, 0) }
        let x = CGFloat(row.start.timeIntervalSince(span.start) / duration) * width
        let end = CGFloat(row.end.timeIntervalSince(span.start) / duration) * width
        return (x, max(0, end - x))
    }

    private func position(_ date: Date, width: CGFloat) -> CGFloat {
        guard let span = model.activeSpan else { return 0 }
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else { return 0 }
        return CGFloat(date.timeIntervalSince(span.start) / duration) * width
    }
}

struct MomentsSheet: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dismiss) private var dismiss

    private var rows: [Milestone] {
        guard let timeline = model.timeline else { return [] }
        return MilestoneList.derive(timeline)
    }

    var body: some View {
        NavigationStack {
            List(rows) { milestone in
                Button(action: {
                    model.jump(to: milestone)
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let epoch = model.timeline?.epoch {
                            let clocks = ClockMath.format(date: milestone.date, epoch: epoch)
                            Text("\(clocks.utc) · \(clocks.eastern) · \(clocks.met)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(milestone.label)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(MilestoneSource.display(milestone.source))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let jump = milestone.jumpUTC {
                            Text("Opens at \(Stamp.clock(jump)) UTC. This capture is outside the playable span.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("milestone-\(milestone.id)")
            }
            .navigationTitle("Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("moments-list")
    }
}
