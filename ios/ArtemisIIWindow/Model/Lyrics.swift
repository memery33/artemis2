import Foundation

/// The spoken line and the lines on either side. Text is the transcript as stored.
struct LyricFocus: Equatable, Sendable {
    var previous: TranscriptLine?
    var current: TranscriptLine?
    var upcoming: TranscriptLine?

    static func focus(at time: Date, track: String, lines: [TranscriptLine]) -> LyricFocus {
        let rows = lines.filter { $0.track == track }.sorted { $0.date < $1.date }
        guard !rows.isEmpty else { return LyricFocus() }
        var index = rows.lastIndex { $0.date <= time }
        if index == nil {
            return LyricFocus(previous: nil, current: nil, upcoming: rows.first)
        }
        let currentIndex = index!
        return LyricFocus(
            previous: currentIndex > 0 ? rows[currentIndex - 1] : nil,
            current: rows[currentIndex],
            upcoming: currentIndex + 1 < rows.count ? rows[currentIndex + 1] : nil
        )
    }
}

enum CrewTint {
    /// Stable colors for the four timeline crew ids. Not a mission color key.
    static func rgba(_ id: String) -> (Double, Double, Double) {
        switch id {
        case "Wiseman": return (0.96, 0.78, 0.42)
        case "Glover": return (0.42, 0.74, 0.96)
        case "Koch": return (0.45, 0.82, 0.62)
        case "Hansen": return (0.86, 0.55, 0.72)
        default: return (1, 1, 1)
        }
    }
}
