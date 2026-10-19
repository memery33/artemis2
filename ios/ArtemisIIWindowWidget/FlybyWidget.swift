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
                    Text(context.state.clock)
                }
                .font(.caption)
            }
            .padding(12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.clock)
                        .font(.caption.monospacedDigit())
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
                Text(context.state.clock)
                    .font(.caption2.monospacedDigit())
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
