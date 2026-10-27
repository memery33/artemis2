import Foundation

enum WindowSide: String, Equatable, Sendable {
    case nikon = "2"
    case cab = "3"
}

struct FramePair: Equatable {
    let current: Frame?
    let next: Frame?
    let index: Int
    /// True when `current` was taken outside the playable span and no Window 3
    /// frame in that span exists to show instead.
    var outsideSpan: Bool = false
}

struct Crossfade: Equatable {
    /// 1 at the incoming frame's own timestamp.
    let mix: Double
    let dominantIsNext: Bool
}

enum FrameSelection {
    static let holdFade: TimeInterval = 4
    static let staleAfter: TimeInterval = 15 * 60
    static let cabinHold: TimeInterval = 9

    /// Frames for one window, in UTC order. The cabin Z9 card stays off the glass.
    /// Capture times are not moved.
    static func frames(_ frames: [Frame], window: WindowSide) -> [Frame] {
        frames.filter { frame in
            if frame.isCabinCard { return false }
            if window == .cab { return frame.instrument == "cab2" }
            return frame.instrument != "cab2"
        }.sorted { $0.date < $1.date }
    }

    static func visiblePair(
        at time: Date,
        window: WindowSide,
        frames all: [Frame],
        spanStart: Date? = nil,
        spanEnd: Date? = nil
    ) -> FramePair {
        let rows = frames(all, window: window)
        if window == .cab, let spanStart, let spanEnd, spanEnd >= spanStart {
            if let chosen = nearestInside(rows, time: time, start: spanStart, end: spanEnd) {
                let index = rows.firstIndex { $0.nasaID == chosen.nasaID } ?? 0
                let next = rows.first { $0.date > chosen.date && $0.date >= spanStart && $0.date <= spanEnd }
                return FramePair(current: chosen, next: next, index: index)
            }
        }
        var index = 0
        while index < rows.count && rows[index].date <= time {
            index += 1
        }
        let current = index > 0 ? rows[index - 1] : nil
        let next = index < rows.count ? rows[index] : nil
        if window == .nikon, let current, time.timeIntervalSince(current.date) > staleAfter {
            return FramePair(current: nil, next: nil, index: 0)
        }
        let outside: Bool
        if window == .cab, let spanStart, let spanEnd, let current {
            outside = current.date < spanStart || current.date > spanEnd
        } else {
            outside = false
        }
        return FramePair(
            current: current,
            next: outside ? nil : next,
            index: max(0, index - 1),
            outsideSpan: outside
        )
    }

    /// Closest capture inside the span. An equal distance keeps the frame already taken.
    private static func nearestInside(_ rows: [Frame], time: Date, start: Date, end: Date) -> Frame? {
        let inside = rows.filter { $0.date >= start && $0.date <= end }
        return inside.min { lhs, rhs in
            let left = abs(lhs.date.timeIntervalSince(time))
            let right = abs(rhs.date.timeIntervalSince(time))
            if left != right { return left < right }
            if (lhs.date <= time) != (rhs.date <= time) { return lhs.date <= time }
            return lhs.date < rhs.date
        }
    }

    /// Photo accessibility name. The live before/after age stays in the visible caption.
    static func photoAccessLabel(_ frame: Frame) -> String {
        "\(frame.credit). \(frame.nasaID). Taken \(Stamp.clock(frame.utc)) UTC."
    }

    static func outsideSpanNotice(frame: Frame, now: Date, includeAge: Bool = true) -> String {
        var parts = ["Outside this span.", "Taken \(Stamp.clock(frame.utc)) UTC · \(frame.nasaID)."]
        if includeAge, let age = clockOffset(now: now, taken: frame.date) {
            parts.append(age)
        }
        return parts.joined(separator: " ")
    }

    static func cabinCard(at time: Date, frames: [Frame]) -> Frame? {
        frames.first { frame in
            frame.isCabinCard
                && time >= frame.date
                && time < frame.date.addingTimeInterval(cabinHold)
        }
    }

    static func crossfade(now: Date, current: Date, next: Date, fade: TimeInterval = holdFade) -> Crossfade {
        guard next > current else { return Crossfade(mix: 0, dominantIsNext: false) }
        let window = min(fade, next.timeIntervalSince(current))
        let start = next.addingTimeInterval(-window)
        let mix: Double
        if now >= next {
            mix = 1
        } else if now > start {
            mix = now.timeIntervalSince(start) / window
        } else {
            mix = 0
        }
        return Crossfade(mix: mix, dominantIsNext: mix >= 0.5)
    }

    /// 0 at the current frame's time, 1 at the next frame's time.
    static func holdProgress(now: Date, current: Date, next: Date?) -> Double {
        guard let next, next > current else { return 0 }
        let span = next.timeIntervalSince(current)
        return min(1, max(0, now.timeIntervalSince(current) / span))
    }

    /// Dark Cab Cam frames are short exposures. The shipped JPEGs are mostly
    /// dark, and the label notes a small bright patch near the middle.
    static func appearance(_ frame: Frame) -> String {
        let note = frame.exposureNote
        if frame.look == "dark", note.range(of: "bright patch", options: .caseInsensitive) != nil {
            return "Mostly dark short exposure, with a small bright patch near the middle. Not brightened."
        }
        if frame.look == "surface" {
            return "Shown as photographed. No window frame is drawn over this picture."
        }
        return "Shown as photographed."
    }

    /// Short age, without the "not moved" sentence. Nil within two seconds.
    static func clockGap(now: Date, taken: Date) -> String? {
        let delta = now.timeIntervalSince(taken)
        if abs(delta) < 2 { return nil }
        let phrase = spanPhrase(abs(delta))
        if delta > 0 { return "\(phrase) before this clock" }
        return "\(phrase) after this clock"
    }

    /// How far the photograph's own timestamp sits from the Orion clock.
    static func clockOffset(now: Date, taken: Date) -> String? {
        guard let gap = clockGap(now: now, taken: taken) else { return nil }
        if now.timeIntervalSince(taken) >= 45 {
            return "Photo taken \(gap). Not moved to match it."
        }
        return "Photo taken \(gap)."
    }

    static func spanPhrase(_ seconds: TimeInterval) -> String {
        let whole = Int(abs(seconds).rounded())
        let minutes = whole / 60
        let secs = whole % 60
        if minutes > 0, secs > 0 { return "\(minutes) min \(secs) s" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(secs) s"
    }

    static func subtitle(at time: Date, track: String, lines: [TranscriptLine]) -> TranscriptLine? {
        let rows = lines.filter { $0.track == track }.sorted { $0.date < $1.date }
        var current: TranscriptLine?
        for row in rows {
            if row.date <= time { current = row } else { break }
        }
        guard let current else { return nil }
        let until = rows.first { $0.date > current.date }?.date ?? current.date.addingTimeInterval(7)
        if time > until || time > current.date.addingTimeInterval(8) { return nil }
        return current
    }
}
