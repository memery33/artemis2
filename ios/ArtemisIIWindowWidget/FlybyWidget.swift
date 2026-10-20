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
                HStack(alignment: .top) {
                    Text(context.state.speaker)
                        .font(HybridFont.text(13, relativeTo: .caption))
                        .foregroundStyle(HybridColor.gold)
                    Spacer()
                    MissionClockText(state: context.state, font: HybridFont.text(12, relativeTo: .caption), showsElapsed: true)
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
                if context.state.playing {
                    Text(context.state.speaker)
                        .font(HybridFont.text(11, relativeTo: .caption2))
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Paused")
                }
            } minimal: {
                if context.state.playing {
                    Text(String(context.state.speaker.prefix(1)))
                        .font(HybridFont.text(11, relativeTo: .caption2))
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Paused")
                }
            }
        }
    }
}

/// "Paused" on the Lock Screen and in the expanded Dynamic Island while `playing` is false.
/// The compact trailing slot uses a pause glyph instead of this word.
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

/// Absolute mission UTC from the last push, plus, on the Lock Screen, elapsed time since the span start.
/// The UTC line is the static string. It is not a `showsHours` timer: that redacts seconds to `--` and
/// painted the day-long count about five minutes fast. The elapsed line ticks only while playing.
/// VoiceOver reads the static strings, so it does not speak a redacted timer.
struct MissionClockText: View {
    var state: FlybyActivityAttributes.ContentState
    var font: Font
    var showsElapsed: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(state.clock)
            if showsElapsed {
                elapsedLine
            }
        }
        .font(font.monospacedDigit())
        .foregroundStyle(HybridColor.cream)
        .multilineTextAlignment(.trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        showsElapsed ? "\(state.clock), \(state.elapsedText)" : state.clock
    }

    @ViewBuilder
    private var elapsedLine: some View {
        if state.playing, state.elapsedEnd > state.elapsedStart {
            (Text(timerInterval: state.elapsedStart...state.elapsedEnd, countsDown: false)
                + Text(" into the flyby"))
        } else {
            Text(state.elapsedText)
        }
    }
}
