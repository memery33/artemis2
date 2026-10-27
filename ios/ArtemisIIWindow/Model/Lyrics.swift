import Foundation

/// The spoken line and the lines on either side. Text is the transcript as stored.
struct LyricFocus: Equatable, Sendable {
    var previous: TranscriptLine?
    var current: TranscriptLine?
    var upcoming: TranscriptLine?

    /// A line older than this, whose audio segment does not cover `time`, is not the caption.
    static let maximumCaptionAge: TimeInterval = 30

    static func focus(
        at time: Date,
        track: String,
        lines: [TranscriptLine],
        segments: [Segment] = []
    ) -> LyricFocus {
        let rows = lines.filter { $0.track == track }.sorted { $0.date < $1.date }
        guard !rows.isEmpty else { return LyricFocus() }
        let index = rows.lastIndex { $0.date <= time }
        guard let index else {
            return LyricFocus(previous: nil, current: nil, upcoming: rows.first)
        }
        let candidate = rows[index]
        let covered = segments.contains { segment in
            segment.track == track
                && candidate.date >= segment.start
                && candidate.date < segment.end
                && time >= segment.start
                && time < segment.end
        }
        let fresh = time.timeIntervalSince(candidate.date) <= maximumCaptionAge
        let current: TranscriptLine? = (covered || fresh) ? candidate : nil
        return LyricFocus(
            previous: current != nil && index > 0 ? rows[index - 1] : nil,
            current: current,
            upcoming: index + 1 < rows.count ? rows[index + 1] : nil
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
