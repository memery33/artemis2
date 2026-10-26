import SwiftUI

struct CrewRow: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var speaker: String? {
        LyricFocus.focus(
            at: model.utc,
            track: model.trackID,
            lines: model.timeline?.lines ?? [],
            segments: model.timeline?.segments ?? []
        ).current?.speaker
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityCrew
        } else {
            standardCrew
        }
    }

    private var standardCrew: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(model.timeline?.crew ?? []) { member in
                    standardChip(member)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            note(lineLimit: 1, scale: 0.8)
        }
    }

    /// One chip per line, name scaled to the column, so a chip cannot sit past the phone.
    private var accessibilityCrew: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.timeline?.crew ?? []) { member in
                accessibilityChip(member)
            }
            note(lineLimit: 2, scale: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func standardChip(_ member: CrewMember) -> some View {
        let speaking = speaker == member.id
        let followed = model.crewID == member.id
        return Button {
            model.follow(member)
        } label: {
            VStack(spacing: 2) {
                letter(member, speaking: speaking, followed: followed)
                Text(member.id)
                    .font(HybridFont.text(10, relativeTo: .caption2))
                    .fontWeight(.medium)
                    .foregroundStyle(HybridColor.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Follow \(member.id)")
        .accessibilityIdentifier("crew-\(member.id)")
    }

    private func accessibilityChip(_ member: CrewMember) -> some View {
        let speaking = speaker == member.id
        let followed = model.crewID == member.id
        return Button {
            model.follow(member)
        } label: {
            HStack(spacing: 8) {
                letter(member, speaking: speaking, followed: followed)
                Text(member.id)
                    .font(HybridFont.text(15, relativeTo: .body))
                    .fontWeight(.semibold)
                    .foregroundStyle(HybridColor.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Follow \(member.id)")
        .accessibilityIdentifier("crew-\(member.id)")
    }

    private func letter(_ member: CrewMember, speaking: Bool, followed: Bool) -> some View {
        Text(String(member.id.prefix(1)))
            .font(HybridFont.display(14, relativeTo: .footnote))
            .foregroundStyle(HybridColor.cream.opacity(0.9))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(speaking ? 0.22 : 0.06)))
            .overlay {
                Circle().strokeBorder(
                    Color(red: CrewTint.rgba(member.id).0, green: CrewTint.rgba(member.id).1, blue: CrewTint.rgba(member.id).2),
                    lineWidth: speaking || followed ? 2 : 1
                )
            }
    }

    private func note(lineLimit: Int, scale: CGFloat) -> some View {
        Text("Names only. No in-flight portrait is bundled.")
            .font(HybridFont.text(10, relativeTo: .caption2))
            .foregroundStyle(dynamicTypeSize.isAccessibilitySize ? HybridColor.dim.opacity(0.75) : HybridColor.cream)
            .lineLimit(lineLimit)
            .minimumScaleFactor(scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("crew-note")
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
            if let name = SpeakerLabel.display(line.speaker) {
                Text(name)
                    .font(prominent ? .caption.weight(.semibold) : .caption2)
                    .foregroundStyle(Color(red: tint.0, green: tint.1, blue: tint.2).opacity(prominent ? 1 : 0.55))
                    .lineLimit(1)
                    .contentTransition(.identity)
            }
            ScrollView(.vertical) {
                TranscriptLineText(
                    text: line.text,
                    font: prominent ? .title3.weight(.semibold) : .body,
                    color: .white.opacity(prominent ? 1 : 0.72),
                    annotationColor: .white.opacity(0.55)
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentTransition(.identity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: prominent ? 132 : 88)
        }
        .id(line.id)
        .transition(.identity)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subtitle-line")
        .accessibilityLabel(TranscriptMarkup.plain(line.text))
    }
}
