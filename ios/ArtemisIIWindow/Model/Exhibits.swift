import Foundation

/// A card is included only when its body is a verbatim Science and Operational Focus
/// sentence from NASA's Guide to the Artemis II Lunar Targeting Plan.
struct ExhibitCard: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var headline: String
    var body: String
    var targetID: String
    var source: String
}

enum ExhibitLibrary {
    static let cards: [ExhibitCard] = [
        ExhibitCard(
            id: "aristarchus-plateau",
            headline: "Aristarchus Plateau",
            body: "Plateau known for its volcanic diversity and the bright Aristarchus crater, looking for color, albedo, and texture variations across the plateau and surrounding mare.",
            targetID: "Aristarchus Plateau",
            source: "Guide to the Artemis II Lunar Targeting Plan, NASA Science. Science and Operational Focus for Aristarchus Plateau."
        ),
        ExhibitCard(
            id: "reiner-gamma",
            headline: "Reiner Gamma",
            body: "Set of bright lunar swirls near highland-mare boundary. Future CLPS landing site.",
            targetID: "Reiner Gamma",
            source: "Guide to the Artemis II Lunar Targeting Plan, NASA Science. Science and Operational Focus for Reiner Gamma."
        ),
        ExhibitCard(
            id: "orientale-basin",
            headline: "Orientale Basin",
            body: "Youngest large basin on the Moon with dark impact melt interior, bright rings, and prominent ejecta with secondary crater chains.",
            targetID: "Orientale Basin",
            source: "Guide to the Artemis II Lunar Targeting Plan, NASA Science. Science and Operational Focus for Orientale Basin."
        )
    ]

    static func frame(for card: ExhibitCard, frames: [Frame]) -> Frame? {
        frames.first { $0.targetID == card.targetID }
    }
}
