import Foundation

enum WindowSide: String, Equatable {
    case nikon = "2"
    case cab = "3"
}

struct FramePair: Equatable {
    let current: Frame?
    let next: Frame?
    let index: Int
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

    static func visiblePair(at time: Date, window: WindowSide, frames all: [Frame]) -> FramePair {
        let rows = frames(all, window: window)
        var index = 0
        while index < rows.count && rows[index].date <= time {
            index += 1
        }
        let current = index > 0 ? rows[index - 1] : nil
        let next = index < rows.count ? rows[index] : nil
        if window == .nikon, let current, time.timeIntervalSince(current.date) > staleAfter {
            return FramePair(current: nil, next: nil, index: 0)
        }
        return FramePair(current: current, next: next, index: max(0, index - 1))
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
