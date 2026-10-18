import Foundation

/// One real timestamp already stored on the timeline. The label quotes or
/// names that record. Closest approach is absent when no source field names it.
struct Milestone: Equatable, Identifiable, Sendable {
    let id: String
    let utc: String
    let date: Date
    let label: String
    /// JSON fields the row was taken from.
    let source: String
    let track: String?
    let window: WindowSide?
    let range: MissionRange?
    /// Set when `date` is outside both playable spans. Playback opens here.
    let jumpUTC: String?
    let jumpDate: Date?
}

enum MilestoneSource {
    /// Readable names for the timeline fields a moment was taken from.
    static func display(_ source: String) -> String {
        source.split(separator: ",").map { label(String($0).trimmingCharacters(in: .whitespaces)) }.joined(separator: ", ")
    }

    private static func label(_ field: String) -> String {
        switch field {
        case "window.start": return "Flyby start"
        case "window.end": return "Flyby end"
        case "window.label": return "Window name"
        case "cab_run.start": return "Cab run start"
        case "cab_run.end": return "Cab run end"
        case "cab_run.label": return "Cab run name"
        case "segments.start": return "Audio start"
        case "segments.end": return "Audio end"
        case "segments.nasa_id": return "NASA ID"
        case "segments.track": return "Audio track"
        case "segments.target_id": return "Target"
        case "lines.utc": return "Transcript time"
        case "lines.speaker": return "Speaker"
        case "lines.text": return "Words"
        case "lines.track": return "Audio track"
        case "lines.nasa_id": return "NASA ID"
        case "targets.name": return "Target name"
        case "frames.utc": return "Photo time"
        case "frames.nasa_id": return "NASA ID"
        case "frames.look": return "Look"
        case "frames.camera_label": return "Camera"
        case "frames.target_id": return "Target"
        case "frames.instrument": return "Instrument"
        default:
            return field.replacingOccurrences(of: ".", with: " ")
        }
    }
}

struct PlaybackCue: Equatable, Sendable {
    var range: MissionRange
    var trackID: String
    var window: WindowSide
    var date: Date
}

struct SpanCoverage: Equatable, Sendable {
    struct Interval: Equatable, Sendable, Identifiable {
        var start: Date
        var end: Date
        var id: String { "\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)" }
    }

    var audio: [Interval]
    var silent: [Interval]
    var photos: [Date]
}

enum MissionClock {
    static func clamp(_ date: Date, to span: TimeSpan) -> Date {
        var target = date
        if target < span.start { target = span.start }
        if target > span.end { target = span.end }
        return target
    }
}

enum MilestoneSeek {
    static func cue(
        for milestone: Milestone,
        timeline: Timeline,
        range: MissionRange,
        trackID: String,
        window: WindowSide
    ) -> PlaybackCue {
        let nextRange = milestone.range ?? range
        let span: TimeSpan = {
            if nextRange == .cab, let cab = timeline.cabRun { return cab }
            return timeline.window
        }()
        let instant = milestone.jumpDate ?? milestone.date
        return PlaybackCue(
            range: nextRange,
            trackID: milestone.track ?? trackID,
            window: milestone.window ?? window,
            date: MissionClock.clamp(instant, to: span)
        )
    }
}

enum MilestoneList {
    static let cabinID = Timeline.cabinID

    static func derive(_ timeline: Timeline) -> [Milestone] {
        var rows: [Milestone] = []
        rows.append(span(
            id: "span:window.start",
            utc: timeline.window.startUTC,
            date: timeline.window.start,
            label: timeline.window.label,
            source: "window.start, window.label",
            window: nil,
            range: .flyby
        ))
        rows.append(span(
            id: "span:window.end",
            utc: timeline.window.endUTC,
            date: timeline.window.end,
            label: timeline.window.label,
            source: "window.end, window.label",
            window: nil,
            range: .flyby
        ))
        if let cab = timeline.cabRun {
            rows.append(span(
                id: "span:cab_run.start",
                utc: cab.startUTC,
                date: cab.start,
                label: cab.label,
                source: "cab_run.start, cab_run.label",
                window: .cab,
                range: .cab
            ))
            rows.append(span(
                id: "span:cab_run.end",
                utc: cab.endUTC,
                date: cab.end,
                label: cab.label,
                source: "cab_run.end, cab_run.label",
                window: .cab,
                range: .cab
            ))
        }

        let segments = timeline.segments.sorted { $0.start < $1.start }
        for segment in segments {
            let target = segment.targetID
            let whereRange = rangeFor(segment.start, timeline: timeline) ?? .flyby
            rows.append(Milestone(
                id: "audio:\(segment.nasaID)",
                utc: segment.startUTC,
                date: segment.start,
                label: target.isEmpty ? segment.nasaID : "\(target) · \(segment.nasaID)",
                source: "segments.start, segments.nasa_id, segments.track, segments.target_id",
                track: segment.track,
                window: whereRange == .cab ? .cab : nil,
                range: whereRange,
                jumpUTC: nil,
                jumpDate: nil
            ))
        }

        var names: [String] = []
        for target in timeline.targets where target.geographic && !names.contains(target.name) {
            names.append(target.name)
        }
        let lines = timeline.lines.enumerated().sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
            return lhs.offset < rhs.offset
        }
        for name in names {
            let token = properNoun(name)
            guard let line = lines.first(where: { containsWord($0.element.text, word: token) })?.element else { continue }
            let speaker = line.speaker.isEmpty ? "" : "\(line.speaker): "
            rows.append(Milestone(
                id: "quote:\(name)",
                utc: line.utc,
                date: line.date,
                label: "\(speaker)\(line.text)",
                source: "lines.utc, lines.speaker, lines.text, lines.track, lines.nasa_id, targets.name",
                track: line.track,
                window: nil,
                range: rangeFor(line.date, timeline: timeline) ?? .flyby,
                jumpUTC: nil,
                jumpDate: nil
            ))
        }

        let frames = timeline.frames.sorted { $0.date < $1.date }
        var seen = Set<String>()
        func addPhoto(_ frame: Frame?, source: String, jumpUTC: String?, jumpDate: Date?) {
            guard let frame, !seen.contains(frame.nasaID) else { return }
            seen.insert(frame.nasaID)
            let geographic = names.contains(frame.targetID)
            let label = geographic
                ? "\(frame.targetID) · \(frame.nasaID)"
                : "\(frame.cameraLabel) · \(frame.nasaID)"
            let whereRange = rangeFor(frame.date, timeline: timeline) ?? .flyby
            let side: WindowSide? = frame.nasaID == cabinID ? nil : (frame.instrument == "cab2" ? .cab : .nikon)
            rows.append(Milestone(
                id: "photo:\(frame.nasaID)",
                utc: frame.utc,
                date: frame.date,
                label: label,
                source: source,
                track: nil,
                window: side,
                range: whereRange,
                jumpUTC: jumpUTC,
                jumpDate: jumpDate
            ))
        }

        for name in names {
            addPhoto(
                frames.first { $0.targetID == name },
                source: "frames.utc, frames.nasa_id, frames.target_id, frames.instrument",
                jumpUTC: nil,
                jumpDate: nil
            )
        }
        addPhoto(
            frames.first { $0.nasaID == cabinID },
            source: "frames.utc, frames.nasa_id, frames.camera_label",
            jumpUTC: nil,
            jumpDate: nil
        )
        let held = frames.last { $0.instrument == "cab2" && $0.date < timeline.window.start }
        addPhoto(
            held,
            source: "frames.utc, frames.nasa_id, frames.look, frames.camera_label, window.start",
            jumpUTC: timeline.window.startUTC,
            jumpDate: timeline.window.start
        )
        var looks: [String] = []
        for frame in frames where frame.instrument == "cab2" {
            guard let look = frame.look, !looks.contains(look) else { continue }
            looks.append(look)
            addPhoto(
                frame,
                source: "frames.utc, frames.nasa_id, frames.look, frames.camera_label",
                jumpUTC: nil,
                jumpDate: nil
            )
        }

        rows.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }
        return rows
    }

    static func coverage(
        timeline: Timeline,
        range: MissionRange,
        track: String,
        window: WindowSide
    ) -> SpanCoverage {
        let span: TimeSpan = {
            if range == .cab, let cab = timeline.cabRun { return cab }
            return timeline.window
        }()
        let clips: [SpanCoverage.Interval] = timeline.segments.compactMap { segment in
            guard segment.track == track else { return nil }
            let start = max(segment.start, span.start)
            let end = min(segment.end, span.end)
            guard end > start else { return nil }
            return SpanCoverage.Interval(start: start, end: end)
        }.sorted { $0.start < $1.start }

        var audio: [SpanCoverage.Interval] = []
        for clip in clips {
            if var last = audio.last, clip.start <= last.end {
                last.end = max(last.end, clip.end)
                audio[audio.count - 1] = last
            } else {
                audio.append(clip)
            }
        }

        var silent: [SpanCoverage.Interval] = []
        var cursor = span.start
        for row in audio {
            if row.start > cursor {
                silent.append(SpanCoverage.Interval(start: cursor, end: row.start))
            }
            cursor = max(cursor, row.end)
        }
        if cursor < span.end {
            silent.append(SpanCoverage.Interval(start: cursor, end: span.end))
        }

        var photos: [Date] = []
        for frame in timeline.frames {
            guard frame.date >= span.start, frame.date <= span.end else { continue }
            let cabin = frame.nasaID == cabinID
            let cab = frame.instrument == "cab2"
            if cabin || (window == .cab ? cab : !cab) {
                photos.append(frame.date)
            }
        }
        photos.sort()
        return SpanCoverage(audio: audio, silent: silent, photos: photos)
    }

    private static func span(
        id: String,
        utc: String,
        date: Date,
        label: String,
        source: String,
        window: WindowSide?,
        range: MissionRange
    ) -> Milestone {
        Milestone(
            id: id,
            utc: utc,
            date: date,
            label: label,
            source: source,
            track: nil,
            window: window,
            range: range,
            jumpUTC: nil,
            jumpDate: nil
        )
    }

    private static func rangeFor(_ date: Date, timeline: Timeline) -> MissionRange? {
        if let cab = timeline.cabRun, date >= cab.start, date <= cab.end { return .cab }
        if date >= timeline.window.start, date <= timeline.window.end { return .flyby }
        return nil
    }

    private static func properNoun(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    private static func containsWord(_ text: String, word: String) -> Bool {
        let haystack = text.lowercased()
        let needle = word.lowercased()
        guard !needle.isEmpty else { return false }
        var from = haystack.startIndex
        while let range = haystack.range(of: needle, range: from..<haystack.endIndex) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !isASCIILetter(haystack[haystack.index(before: range.lowerBound)])
            let afterOK = range.upperBound == haystack.endIndex
                || !isASCIILetter(haystack[range.upperBound])
            if beforeOK && afterOK { return true }
            from = range.upperBound
        }
        return false
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        return (65...90).contains(value) || (97...122).contains(value)
    }
}
