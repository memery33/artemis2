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
                TranscriptLineText(
                    text: context.state.nextMilestone,
                    font: HybridFont.text(15, relativeTo: .subheadline),
                    color: HybridColor.cream,
                    annotationColor: HybridColor.dim,
                    lineLimit: 2
                )
                HStack(alignment: .top) {
                    if let name = SpeakerLabel.display(context.state.speaker) {
                        Text(name)
                            .font(HybridFont.text(13, relativeTo: .caption))
                            .foregroundStyle(HybridColor.gold)
                    }
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
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let name = SpeakerLabel.display(context.state.speaker) {
                        Text(name)
                            .font(HybridFont.text(12, relativeTo: .caption))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.trailing, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        PausedMarker(playing: context.state.playing, font: HybridFont.text(12, relativeTo: .caption))
                        ProgressView(value: context.state.progress)
                            .tint(HybridColor.gold)
                        TranscriptLineText(
                            text: context.state.nextMilestone,
                            font: HybridFont.text(12, relativeTo: .caption),
                            color: .primary,
                            annotationColor: .secondary,
                            lineLimit: 1,
                            minimumScaleFactor: 0.7
                        )
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                MissionClockText(state: context.state, font: HybridFont.text(11, relativeTo: .caption2))
            } compactTrailing: {
                if context.state.playing, let name = SpeakerLabel.display(context.state.speaker) {
                    Text(name)
                        .font(HybridFont.text(11, relativeTo: .caption2))
                } else if !context.state.playing {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Paused")
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Playing")
                }
            } minimal: {
                if context.state.playing, let name = SpeakerLabel.display(context.state.speaker) {
                    let initial: String = String(name.prefix(1))
                    Text(initial)
                        .font(HybridFont.text(11, relativeTo: .caption2))
                } else if !context.state.playing {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Paused")
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Playing")
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

/// Absolute mission UTC and, on the Lock Screen, elapsed time. Both strings come from the last push.
/// Neither is a timer: a ticking elapsed count ran ahead of the UTC line, then stuck at the span length.
/// VoiceOver reads the same static strings.
struct MissionClockText: View {
    var state: FlybyActivityAttributes.ContentState
    var font: Font
    var showsElapsed: Bool = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(state.clock)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if showsElapsed, !state.elapsedText.isEmpty {
                Text(state.elapsedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .font(font.monospacedDigit())
        .foregroundStyle(HybridColor.cream)
        .multilineTextAlignment(.trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard showsElapsed, !state.elapsedText.isEmpty else { return state.clock }
        return "\(state.clock), \(state.elapsedText)"
    }
}
