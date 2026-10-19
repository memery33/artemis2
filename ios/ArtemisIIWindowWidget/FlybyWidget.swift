import ActivityKit
import SwiftUI
import WidgetKit

extension FlybyActivityAttributes: ActivityAttributes {}

@main
struct FlybyWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlybyLiveActivityWidget()
    }
}

struct FlybyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlybyActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.title)
                    .font(.headline)
                PausedMarker(playing: context.state.playing, font: .caption.weight(.semibold))
                ProgressView(value: context.state.progress)
                    .accessibilityLabel("Flyby progress")
                Text(context.state.nextMilestone)
                    .font(.subheadline)
                HStack {
                    Text(context.state.speaker)
                    Spacer()
                    MissionClockText(state: context.state, font: .caption)
                }
            }
            .padding(12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MissionClockText(state: context.state, font: .caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.speaker)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        PausedMarker(playing: context.state.playing, font: .caption.weight(.semibold))
                        ProgressView(value: context.state.progress)
                        Text(context.state.nextMilestone)
                            .font(.caption)
                    }
                }
            } compactLeading: {
                MissionClockText(state: context.state, font: .caption2)
            } compactTrailing: {
                if let paused = FlybyActivityAttributes.pausedLabel(playing: context.state.playing) {
                    Text(paused)
                        .font(.caption2.weight(.semibold))
                } else {
                    Text(context.state.speaker)
                        .font(.caption2)
                }
            } minimal: {
                Text(String(context.state.speaker.prefix(1)))
                    .font(.caption2)
            }
        }
    }
}

/// "Paused" on the Lock Screen and in the Dynamic Island while `playing` is false.
private struct PausedMarker: View {
    var playing: Bool
    var font: Font

    var body: some View {
        if let label = FlybyActivityAttributes.pausedLabel(playing: playing) {
            Text(label)
                .font(font)
        }
    }
}

/// Absolute mission UTC. Static text, replaced when playback pushes a new state on play, pause, seek, speaker change, or span end, and at most every 15 seconds while playing. A forced push is not held for that 15-second cadence. A `Text(timerInterval:)` of minutes and seconds renders as `--` and does not advance.
struct MissionClockText: View {
    var state: FlybyActivityAttributes.ContentState
    var font: Font

    var body: some View {
        Text(state.clock)
            .font(font.monospacedDigit())
    }
}
