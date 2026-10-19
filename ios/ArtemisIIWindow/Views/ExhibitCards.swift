import SwiftUI

struct ExhibitCards: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ExhibitLibrary.cards) { card in
                cardView(card)
            }
        }
    }

    private func cardView(_ card: ExhibitCard) -> some View {
        let frame = ExhibitLibrary.frame(for: card, frames: model.timeline?.frames ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            if let frame, let image = model.photo(frame, maxPixel: 720) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
            }
            Text(card.headline)
                .font(.headline)
                .foregroundStyle(.white)
            Text(card.body)
                .font(.body)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Text(card.source)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            if let frame {
                Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC · \(frame.credit)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exhibit-\(card.id)")
        .task(id: frame?.nasaID) {
            if let frame {
                model.prefetch(frame, maxPixel: 720)
            }
        }
    }
}
