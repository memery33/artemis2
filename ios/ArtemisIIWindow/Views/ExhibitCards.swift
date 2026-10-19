import SwiftUI

struct ExhibitCards: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var opened: ExhibitCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ExhibitLibrary.cards) { card in
                exhibitCard(card)
            }
        }
        .sheet(item: $opened) { card in
            ExhibitSheet(card: card)
        }
    }

    /// The credit sits outside the button. A button combines its label into one
    /// accessibility element, which made the photo-credit query return the whole card.
    private func exhibitCard(_ card: ExhibitCard) -> some View {
        let frame = ExhibitLibrary.frame(for: card, frames: model.timeline?.frames ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                opened = card
            } label: {
                cardFace(card, frame: frame)
            }
            .buttonStyle(.plain)
            CreditLine()
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("photo-credit")
                .accessibilityLabel("Credit: NASA/Artemis II Crew")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exhibit-\(card.id)")
        .accessibilityHint("Opens the exhibit")
        .task(id: frame?.nasaID) {
            if let frame {
                model.prefetch(frame, maxPixel: 720)
            }
        }
    }

    private func cardFace(_ card: ExhibitCard, frame: Frame?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
    }
}

private struct ExhibitSheet: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dismiss) private var dismiss
    var card: ExhibitCard

    var body: some View {
        let frame = ExhibitLibrary.frame(for: card, frames: model.timeline?.frames ?? [])
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let frame, let image = model.photo(frame, maxPixel: 1200) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                            .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
                    }
                    Text(card.headline)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(card.body)
                        .font(.body)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.source)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    if let frame {
                        Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    CreditLine()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .navigationTitle(card.headline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("exhibit-sheet")
        .task(id: frame?.nasaID) {
            if let frame {
                model.prefetch(frame, maxPixel: 1200)
            }
        }
    }
}
