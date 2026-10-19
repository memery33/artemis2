import SwiftUI

struct CrewRow: View {
    @EnvironmentObject private var model: PlaybackModel

    private var speaker: String? {
        LyricFocus.focus(
            at: model.utc,
            track: model.trackID,
            lines: model.timeline?.lines ?? []
        ).current?.speaker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(model.timeline?.crew ?? []) { member in
                        let speaking = speaker == member.id
                        let followed = model.crewID == member.id
                        Button {
                            model.follow(member)
                        } label: {
                            VStack(spacing: 4) {
                                Text(String(member.id.prefix(1)))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 52)
                                    .background(Circle().fill(Color.white.opacity(speaking ? 0.22 : 0.06)))
                                    .overlay {
                                        Circle().strokeBorder(
                                            Color(red: CrewTint.rgba(member.id).0, green: CrewTint.rgba(member.id).1, blue: CrewTint.rgba(member.id).2),
                                            lineWidth: speaking || followed ? 3 : 1
                                        )
                                    }
                                Text(member.id)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(followed ? 1 : 0.7))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(minWidth: 64, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Follow \(member.id)")
                        .accessibilityIdentifier("crew-\(member.id)")
                    }
                }
            }
            Text("No separate in-flight portrait is bundled. The marks are the crew names on the timeline.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("crew-note")
        }
    }
}

struct LyricLines: View {
    var focus: LyricFocus
    @State private var shown: LyricFocus

    init(focus: LyricFocus) {
        self.focus = focus
        _shown = State(initialValue: focus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previous = shown.previous {
                verse(previous, prominent: false)
            }
            if let current = shown.current {
                verse(current, prominent: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: focus) { _, newFocus in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                shown = newFocus
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func verse(_ line: TranscriptLine, prominent: Bool) -> some View {
        let tint = CrewTint.rgba(line.speaker)
        return VStack(alignment: .leading, spacing: 2) {
            Text(line.speaker)
                .font(prominent ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(Color(red: tint.0, green: tint.1, blue: tint.2).opacity(prominent ? 1 : 0.55))
                .lineLimit(1)
                .contentTransition(.identity)
            Text(line.text)
                .font(prominent ? .title3.weight(.semibold) : .body)
                .foregroundStyle(.white.opacity(prominent ? 1 : 0.72))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentTransition(.identity)
        }
        .id(line.id)
        .transition(.identity)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subtitle-line")
        .accessibilityLabel(line.text)
    }
}
