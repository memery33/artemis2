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
            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.title)
                    .font(HybridFont.display(20, relativeTo: .headline))
                    .foregroundStyle(HybridColor.cream)
                PausedMarker(playing: context.state.playing, font: HybridFont.text(12, relativeTo: .caption))
                ProgressView(value: context.state.progress)
                    .tint(HybridColor.gold)
                    .accessibilityLabel("Flyby progress")
                Text(context.state.nextMilestone)
                    .font(HybridFont.text(15, relativeTo: .subheadline))
                    .foregroundStyle(HybridColor.cream)
                    .lineLimit(2)
                HStack {
                    Text(context.state.speaker)
                        .font(HybridFont.text(13, relativeTo: .caption))
                        .foregroundStyle(HybridColor.gold)
                    Spacer()
                    MissionClockText(state: context.state, font: HybridFont.text(12, relativeTo: .caption))
                }
            }
            .padding(14)
            .containerBackground(HybridColor.ground, for: .widget)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MissionClockText(state: context.state, font: HybridFont.text(12, relativeTo: .caption))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.speaker)
                        .font(HybridFont.text(12, relativeTo: .caption))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        PausedMarker(playing: context.state.playing, font: HybridFont.text(12, relativeTo: .caption))
                        ProgressView(value: context.state.progress)
                            .tint(HybridColor.gold)
                        Text(context.state.nextMilestone)
                            .font(HybridFont.text(12, relativeTo: .caption))
                            .lineLimit(2)
                    }
                }
            } compactLeading: {
                MissionClockText(state: context.state, font: HybridFont.text(11, relativeTo: .caption2))
            } compactTrailing: {
                if let paused = FlybyActivityAttributes.pausedLabel(playing: context.state.playing) {
                    Text(paused)
                        .font(HybridFont.text(11, relativeTo: .caption2))
                        .fontWeight(.semibold)
                } else {
                    Text(context.state.speaker)
                        .font(HybridFont.text(11, relativeTo: .caption2))
                }
            } minimal: {
                Text(String(context.state.speaker.prefix(1)))
                    .font(HybridFont.text(11, relativeTo: .caption2))
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
                .fontWeight(.semibold)
                .foregroundStyle(HybridColor.gold)
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
            .foregroundStyle(HybridColor.cream)
    }
}
