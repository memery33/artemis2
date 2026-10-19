import SwiftUI

struct ExhibitCards: View {
    @EnvironmentObject private var model: PlaybackModel
    @State private var opened: ExhibitCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ExhibitLibrary.cards) { card in
                Button {
                    opened = card
                } label: {
                    cardBody(card, showsSource: false)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("exhibit-\(card.id)")
                .accessibilityHint("Opens the exhibit")
            }
        }
        .sheet(item: $opened) { card in
            ExhibitSheet(card: card)
        }
    }

    private func cardBody(_ card: ExhibitCard, showsSource: Bool) -> some View {
        let frame = ExhibitLibrary.frame(for: card, frames: model.timeline?.frames ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            if let frame, let image = model.photo(frame, maxPixel: 720) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: showsSource ? 220 : 140)
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
            if showsSource {
                Text(card.source)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if let frame {
                    Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            CreditLine()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: frame?.nasaID) {
            if let frame {
                model.prefetch(frame, maxPixel: 720)
            }
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
