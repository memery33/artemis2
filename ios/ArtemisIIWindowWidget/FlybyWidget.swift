import ActivityKit
import SwiftUI
import WidgetKit

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
                        ProgressView(value: context.state.progress)
                        Text(context.state.nextMilestone)
                            .font(.caption)
                    }
                }
            } compactLeading: {
                MissionClockText(state: context.state, font: .caption2)
            } compactTrailing: {
                Text(context.state.speaker)
                    .font(.caption2)
            } minimal: {
                Text(String(context.state.speaker.prefix(1)))
                    .font(.caption2)
            }
        }
    }
}

/// While playback is running, the hour is fixed and the minutes and seconds are a
/// count-up under one hour, so the widget draws real seconds at 1x. A paused
/// activity shows the last `HH:mm:ss` string.
struct MissionClockText: View {
    var state: FlybyActivityAttributes.ContentState
    var font: Font

    var body: some View {
        Group {
            if state.playing {
                HStack(spacing: 0) {
                    Text(state.hourText)
                    Text(
                        timerInterval: state.missionTimer,
                        pauseTime: nil,
                        countsDown: false,
                        showsHours: false
                    )
                }
            } else {
                Text(state.clock)
            }
        }
        .font(font.monospacedDigit())
    }
}
