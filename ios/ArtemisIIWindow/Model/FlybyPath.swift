import Foundation

/// One Moon-centered geometric state from the bundled Horizons table.
struct PathSample: Equatable, Sendable {
    var date: Date
    var x: Double
    var y: Double
    var z: Double
    var rangeKm: Double
}

/// Closest approach derived from the tabulated ranges. Nothing here is typed in by hand.
struct ClosestApproach: Equatable, Sendable {
    var date: Date
    var rangeKm: Double
    var altitudeKm: Double
    var radiusKm: Double
}

struct FlybyDocument: Decodable, Sendable {
    var source: String
    var query: String
    var frame: String
    var radiusKm: Double
    var radiusNote: String
    var samples: [Row]

    struct Row: Decodable, Sendable {
        var t: String
        var x: Double
        var y: Double
        var z: Double
        var rangeKm: Double
    }
}

struct SunDocument: Decodable, Sendable {
    var source: String
    var query: String
    var frame: String
    var samples: [Row]

    struct Row: Decodable, Sendable {
        var t: String
        var lonEast: Double
        var lat: Double
    }
}

struct SunSample: Equatable, Sendable {
    var date: Date
    var longitudeEast: Double
    var latitude: Double
}

/// Sub-solar point of the Moon in IAU MOON_ME, from Horizons quantity 15.
enum SolarEphemeris {
    static let bundled: (document: SunDocument, samples: [SunSample])? = {
        guard let document = load() else { return nil }
        let rows = samples(in: document)
        guard !rows.isEmpty else { return nil }
        return (document, rows)
    }()

    static func load(from bundle: Bundle = .main) -> SunDocument? {
        guard let url = bundle.url(forResource: "horizons_sun_moon", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SunDocument.self, from: data)
    }

    static func samples(in document: SunDocument) -> [SunSample] {
        document.samples.compactMap { row in
            guard let date = try? ISO8601.parse(row.t) else { return nil }
            return SunSample(date: date, longitudeEast: row.lonEast, latitude: row.lat)
        }
    }

    /// Unit vector from the Moon's center toward the Sun. Longitude and latitude are interpolated; the vector is not invented.
    static func direction(at date: Date, samples: [SunSample]) -> (x: Double, y: Double, z: Double)? {
        guard let first = samples.first else { return nil }
        if date <= first.date {
            return MoonFrame.unit(latitude: first.latitude, longitudeEast: first.longitudeEast)
        }
        guard let last = samples.last else { return nil }
        if date >= last.date {
            return MoonFrame.unit(latitude: last.latitude, longitudeEast: last.longitudeEast)
        }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if samples[mid].date <= date {
                low = mid
            } else {
                high = mid
            }
        }
        let start = samples[low]
        let end = samples[high]
        let span = end.date.timeIntervalSince(start.date)
        let portion = span > 0 ? date.timeIntervalSince(start.date) / span : 0
        let longitude = start.longitudeEast + shortestTurn(from: start.longitudeEast, to: end.longitudeEast) * portion
        let latitude = start.latitude + (end.latitude - start.latitude) * portion
        return MoonFrame.unit(latitude: latitude, longitudeEast: longitude)
    }

    /// Signed shortest step from `start` to `end`, in degrees. A step across 0/360 does not travel the long way around.
    static func shortestTurn(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

enum FlybyEphemeris {
    static let bundled: (document: FlybyDocument, samples: [PathSample])? = {
        guard let document = load() else { return nil }
        let rows = samples(in: document)
        guard !rows.isEmpty else { return nil }
        return (document, rows)
    }()

    static func load(from bundle: Bundle = .main) -> FlybyDocument? {
        guard let url = bundle.url(forResource: "horizons_orion_moon", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(FlybyDocument.self, from: data)
    }

    /// Rows are already IAU MOON_ME body-fixed coordinates (sub-observer longitude, latitude, and range).
    static func samples(in document: FlybyDocument) -> [PathSample] {
        document.samples.compactMap { row in
            guard let date = try? ISO8601.parse(row.t) else { return nil }
            return PathSample(date: date, x: row.x, y: row.y, z: row.z, rangeKm: row.rangeKm)
        }
    }
}

enum FlybyPath {
    static func arcLengths(_ samples: [PathSample]) -> [Double] {
        var lengths = Array(repeating: 0.0, count: samples.count)
        guard samples.count > 1 else { return lengths }
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let sample = samples[index]
            let dx = sample.x - previous.x
            let dy = sample.y - previous.y
            let dz = sample.z - previous.z
            lengths[index] = lengths[index - 1] + (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        return lengths
    }

    static func fraction(at date: Date, samples: [PathSample]) -> Double {
        fraction(at: date, samples: samples, lengths: arcLengths(samples))
    }

    static func fraction(at date: Date, samples: [PathSample], lengths: [Double]) -> Double {
        guard let first = samples.first, let last = samples.last, let total = lengths.last, total > 0 else {
            return 0
        }
        if date <= first.date { return 0 }
        if date >= last.date { return 1 }
        let (low, high) = segment(containing: date, samples: samples)
        let span = samples[high].date.timeIntervalSince(samples[low].date)
        let portion = span > 0 ? date.timeIntervalSince(samples[low].date) / span : 0
        let distance = lengths[low] + (lengths[high] - lengths[low]) * portion
        return distance / total
    }

    static func date(atFraction fraction: Double, samples: [PathSample]) -> Date {
        date(atFraction: fraction, samples: samples, lengths: arcLengths(samples))
    }

    static func date(atFraction fraction: Double, samples: [PathSample], lengths: [Double]) -> Date {
        guard let total = lengths.last, total > 0, samples.count > 1 else {
            return samples.first?.date ?? Date(timeIntervalSinceReferenceDate: 0)
        }
        let target = total * min(1, max(0, fraction))
        var low = 0
        var high = lengths.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if lengths[mid] <= target {
                low = mid
            } else {
                high = mid
            }
        }
        let span = lengths[high] - lengths[low]
        let portion = span > 0 ? (target - lengths[low]) / span : 0
        let interval = samples[high].date.timeIntervalSince(samples[low].date)
        return samples[low].date.addingTimeInterval(interval * portion)
    }

    static func position(at date: Date, samples: [PathSample]) -> (x: Double, y: Double, z: Double)? {
        guard let first = samples.first else { return nil }
        if date <= first.date { return (first.x, first.y, first.z) }
        if let last = samples.last, date >= last.date { return (last.x, last.y, last.z) }
        let (low, high) = segment(containing: date, samples: samples)
        let span = samples[high].date.timeIntervalSince(samples[low].date)
        let portion = span > 0 ? date.timeIntervalSince(samples[low].date) / span : 0
        let start = samples[low]
        let end = samples[high]
        return (
            start.x + (end.x - start.x) * portion,
            start.y + (end.y - start.y) * portion,
            start.z + (end.z - start.z) * portion
        )
    }

    /// Time and altitude of closest approach from the tabulated apparent ranges.
    ///
    /// Horizons quantity 20 is apparent range, not a geometric range. The vertex
    /// of the parabola through the lowest sample and its two neighbors is the
    /// refined instant. Altitude is that range minus the radius in the Horizons
    /// header, which the caller passes in from the file.
    static func closestApproach(_ samples: [PathSample], radiusKm: Double) -> ClosestApproach? {
        guard let lowest = samples.enumerated().min(by: { $0.element.rangeKm < $1.element.rangeKm }) else {
            return nil
        }
        let index = lowest.offset
        let sample = lowest.element
        guard index > 0, index + 1 < samples.count else {
            return ClosestApproach(
                date: sample.date,
                rangeKm: sample.rangeKm,
                altitudeKm: sample.rangeKm - radiusKm,
                radiusKm: radiusKm
            )
        }
        let before = samples[index - 1].rangeKm
        let middle = sample.rangeKm
        let after = samples[index + 1].rangeKm
        let curvature = (before + after) / 2 - middle
        let slope = (after - before) / 2
        let vertex: Double
        if abs(curvature) > 1e-9 {
            vertex = min(1, max(-1, -slope / (2 * curvature)))
        } else {
            vertex = 0
        }
        let range = curvature * vertex * vertex + slope * vertex + middle
        let step = samples[index + 1].date.timeIntervalSince(samples[index - 1].date) / 2
        let date = sample.date.addingTimeInterval(vertex * step)
        return ClosestApproach(
            date: date,
            rangeKm: range,
            altitudeKm: range - radiusKm,
            radiusKm: radiusKm
        )
    }

    /// 0 at the first sample, 1 at closest approach. Built from tabulated range.
    static func approachIntensity(at date: Date, samples: [PathSample], approach: ClosestApproach) -> Double {
        guard let first = samples.first,
              let place = position(at: date, samples: samples) else {
            return 0
        }
        let range = (place.x * place.x + place.y * place.y + place.z * place.z).squareRoot()
        let span = first.rangeKm - approach.rangeKm
        guard span > 1 else { return 0 }
        return min(1, max(0, (first.rangeKm - range) / span))
    }

    private static func segment(containing date: Date, samples: [PathSample]) -> (Int, Int) {
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if samples[mid].date <= date {
                low = mid
            } else {
                high = mid
            }
        }
        return (low, high)
    }
}

/// One projected sample of a bright path segment. Coordinates are screen points.
struct PathScreenSample: Equatable, Sendable {
    var date: Date
    var x: Double
    var y: Double
}

/// Playable clock spans. Dragging the path uses only these, never the dim context arc.
struct PathSpan: Equatable, Hashable, Sendable {
    var start: Date
    var end: Date
}

struct PathScrubChoice: Equatable, Sendable {
    var date: Date
    var span: PathSpan
}

enum PathScrub {
    /// The finger has to be this close, in points, to a pin on another span before that pin is chosen.
    static let reach: Double = 24

    static func contains(_ date: Date, spans: [PathSpan]) -> Bool {
        spans.contains { date >= $0.start && date <= $0.end }
    }

    /// Horizontal finger travel scrubs the current span. One panel width covers that span, which is about 4 s/pt on a phone.
    /// The sign is the on-screen direction Orion moves, so dragging along the path goes forward. The span end is only the exact clamp.
    static func drag(
        anchorDate: Date,
        translationX: Double,
        panelWidth: Double,
        samples: [PathScreenSample],
        span: PathSpan
    ) -> PathScrubChoice? {
        let duration = span.end.timeIntervalSince(span.start)
        guard duration > 0 else { return PathScrubChoice(date: clamp(anchorDate, to: span), span: span) }
        let width = max(panelWidth, 1)
        let sign = forwardSign(at: anchorDate, samples: samples)
        let shifted = anchorDate.addingTimeInterval(duration * translationX * sign / width)
        return PathScrubChoice(date: clamp(shifted, to: span), span: span)
    }

    /// +1 when the projected path moves right as time increases, −1 when it moves left.
    static func forwardSign(at date: Date, samples: [PathScreenSample]) -> Double {
        guard samples.count >= 2 else { return 1 }
        var index = 0
        while index < samples.count - 1, samples[index + 1].date < date {
            index += 1
        }
        let local = samples[index + 1].x - samples[index].x
        if abs(local) >= 0.01 { return local > 0 ? 1 : -1 }
        let net = samples[samples.count - 1].x - samples[0].x
        if abs(net) >= 0.01 { return net > 0 ? 1 : -1 }
        return 1
    }

    private static func clamp(_ date: Date, to span: PathSpan) -> Date {
        if date < span.start { return span.start }
        if date > span.end { return span.end }
        return date
    }

    /// Pulls a silent instant onto the nearest recording inside the same span.
    /// Returns nil when the span has no recording to land on.
    static func snap(_ date: Date, recordings: [PathSpan], span: PathSpan) -> Date? {
        let clips = recordings.compactMap { clip -> PathSpan? in
            let start = max(clip.start, span.start)
            let end = min(clip.end, span.end)
            guard end > start else { return nil }
            return PathSpan(start: start, end: end)
        }
        guard !clips.isEmpty else { return nil }
        if clips.contains(where: { date >= $0.start && date < $0.end }) {
            return date
        }
        var best: (date: Date, distance: TimeInterval)?
        for clip in clips {
            let landed = min(max(date, clip.start), clip.end.addingTimeInterval(-0.05))
            let distance = abs(landed.timeIntervalSince(date))
            if best == nil || distance < best!.distance {
                best = (landed, distance)
            }
        }
        return best?.date
    }
}

/// IAU names placed on the MOON_ME globe. Coordinates are planetographic,
/// east-positive, from the USGS Gazetteer of Planetary Nomenclature.
/// These are already body-fixed. They are not rotated by the lunar angle W.
struct LunarSite: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var feature: String
    var latitude: Double
    var longitudeEast: Double
    var source: String
}

enum LunarSites {
    static let marked: [LunarSite] = [
        LunarSite(
            id: "aristarchus",
            label: "Aristarchus",
            feature: "Aristarchus",
            latitude: 23.73,
            longitudeEast: -47.49,
            source: "USGS Gazetteer of Planetary Nomenclature, feature 380, Moon, crater, center latitude 23.73, center longitude -47.49, planetographic +East. Approved by the IAU."
        ),
        LunarSite(
            id: "reiner-gamma",
            label: "Reiner Gamma",
            feature: "Reiner Gamma",
            latitude: 7.39,
            longitudeEast: -58.96,
            source: "USGS Gazetteer of Planetary Nomenclature, feature 4987, Moon, albedo feature, center latitude 7.39, center longitude -58.96, planetographic +East. Approved by the IAU."
        ),
        LunarSite(
            id: "orientale",
            label: "Orientale",
            feature: "Mare Orientale",
            latitude: -19.87,
            longitudeEast: -94.67,
            source: "USGS Gazetteer of Planetary Nomenclature, feature 3685, Mare Orientale, Moon, center latitude -19.87, center longitude -94.67, planetographic +East. Approved by the IAU. The label says Orientale; the named feature is Mare Orientale."
        )
    ]
}

/// A Closest approach tap lands on the nearest real frame or recording that
/// already sits inside a playable span. The card names the Horizons instant,
/// the altitude, and how long before that the photograph was taken.
struct ClosestApproachLanding: Equatable, Sendable {
    var date: Date
    var range: MissionRange
    var trackID: String
    var window: WindowSide
    var frameID: String
    /// Horizons clock and altitude, then the gap to the nearest crew photo.
    var gap: String

    static func make(timeline: Timeline) -> ClosestApproachLanding? {
        guard let approach = approach() else { return nil }
        var best: Date?
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        func consider(_ date: Date) {
            guard span(containing: date, timeline: timeline) != nil else { return }
            let distance = abs(date.timeIntervalSince(approach.date))
            let replace: Bool
            if let current = best {
                replace = prefers(
                    date,
                    distance: distance,
                    over: current,
                    currentDistance: bestDistance,
                    approach: approach.date
                )
            } else {
                replace = true
            }
            if replace {
                best = date
                bestDistance = distance
            }
        }
        for frame in timeline.frames where !frame.isCabinCard {
            consider(frame.date)
        }
        for segment in timeline.segments {
            consider(closestPoint(on: segment, to: approach.date))
        }
        guard let seek = best, let placed = span(containing: seek, timeline: timeline) else { return nil }
        let side = window(at: seek, timeline: timeline)
        let track = trackID(for: placed.range, timeline: timeline, approach: approach.date)
        let shown = HybridFrames.shown(at: seek, side: side, timeline: timeline, span: placed.span)
        let taken = shown?.date ?? seek
        return ClosestApproachLanding(
            date: seek,
            range: placed.range,
            trackID: track,
            window: side,
            frameID: shown?.nasaID ?? "",
            gap: gap(approach: approach, taken: taken)
        )
    }

    /// Shown when no bundled frame or recording falls inside a playable span.
    /// Time and altitude come from the Horizons table, not a typed-in clock.
    static func missingNote() -> String? {
        guard let approach = approach() else { return nil }
        return "\(headline(approach)) No crew recording at that moment."
    }

    private static func approach() -> ClosestApproach? {
        FlybyEphemeris.bundled.flatMap {
            FlybyPath.closestApproach($0.samples, radiusKm: $0.document.radiusKm)
        }
    }

    /// Closed at both ends, so a frame timestamped on the span end still lands inside it.
    private static func span(containing date: Date, timeline: Timeline) -> (range: MissionRange, span: TimeSpan)? {
        if let cab = timeline.cabRun, contains(date, cab) {
            return (.cab, cab)
        }
        if contains(date, timeline.window) {
            return (.flyby, timeline.window)
        }
        return nil
    }

    private static func contains(_ date: Date, _ span: TimeSpan) -> Bool {
        date >= span.start && date <= span.end
    }

    /// Audio for the span the photograph is in. An empty span uses that span's track.
    private static func trackID(for range: MissionRange, timeline: Timeline, approach: Date) -> String {
        let rows = timeline.segments.filter { segmentRange($0, timeline: timeline) == range }
        if let nearest = rows.min(by: {
            audioDistance($0, to: approach) < audioDistance($1, to: approach)
        }) {
            return nearest.track
        }
        return range == .cab ? "pcd2" : "pcd3"
    }

    private static func segmentRange(_ segment: Segment, timeline: Timeline) -> MissionRange {
        if let cab = timeline.cabRun, segment.start <= cab.end, segment.end >= cab.start {
            return .cab
        }
        return .flyby
    }

    private static func closestPoint(on segment: Segment, to date: Date) -> Date {
        if date < segment.start { return segment.start }
        if date > segment.end { return segment.end }
        return date
    }

    private static func audioDistance(_ segment: Segment, to date: Date) -> TimeInterval {
        abs(closestPoint(on: segment, to: date).timeIntervalSince(date))
    }

    /// Cab Cam when the nearest still is a GoPro frame, so an hours-old Nikon
    /// exposure is not left up in its place.
    private static func window(at date: Date, timeline: Timeline) -> WindowSide {
        let frames = timeline.frames.filter { !$0.isCabinCard }
        guard let nearest = frames.min(by: { lhs, rhs in
            prefers(
                lhs.date,
                distance: abs(lhs.date.timeIntervalSince(date)),
                over: rhs.date,
                currentDistance: abs(rhs.date.timeIntervalSince(date)),
                approach: date
            )
        }) else {
            return .nikon
        }
        return nearest.instrument == "cab2" ? .cab : .nikon
    }

    static func prefers(
        _ candidate: Date,
        distance: TimeInterval,
        over current: Date,
        currentDistance: TimeInterval,
        approach: Date
    ) -> Bool {
        if distance != currentDistance { return distance < currentDistance }
        let candidateTaken = candidate <= approach
        let currentTaken = current <= approach
        if candidateTaken != currentTaken { return candidateTaken }
        return candidate < current
    }

    /// The Horizons vertex rounded once, to the nearest second. The printed clock
    /// and the gap to the photograph both use this instant.
    static func displayedInstant(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded())
    }

    private static func gap(approach: ClosestApproach, taken: Date) -> String {
        let sentence = headline(approach)
        let delta = displayedInstant(approach.date).timeIntervalSince(taken)
        if abs(delta) < 2 { return sentence }
        let phrase = FrameSelection.spanPhrase(abs(delta))
        if delta > 0 {
            return "\(sentence) The nearest crew photo was taken \(phrase) earlier."
        }
        return "\(sentence) The nearest crew photo was taken \(phrase) later."
    }

    /// Whole kilometers. 6,545.22 km from the vertex is the sourced 6,545 km.
    /// The radius is the Horizons center radius, not a separate surface model.
    private static func headline(_ approach: ClosestApproach) -> String {
        let altitude = surfaceKilometers(approach.altitudeKm)
        let radius = radiusKilometers(approach.radiusKm)
        let clock = ClockMath.utcText(displayedInstant(approach.date))
        return "Closest approach: \(clock), \(altitude) km above the Moon's \(radius) km mean radius (NASA/JPL Horizons)."
    }

    private static func radiusKilometers(_ radiusKm: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: radiusKm)) ?? String(format: "%.1f", radiusKm)
    }

    private static func surfaceKilometers(_ altitudeKm: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        let whole = altitudeKm.rounded()
        return formatter.string(from: NSNumber(value: whole)) ?? String(format: "%.0f", whole)
    }
}

enum MoonFrame {
    /// IAU MOON_ME body-fixed axes: +X at east-longitude 0 (the mean-Earth meridian),
    /// +Y toward 90° east, +Z north. The bundled Horizons table is already in this
    /// frame (observer sub-longitude and sub-latitude, quantity 14). It is not the
    /// BODY EQUATOR node-of-date vector frame, whose +X is the equator node.
    static func unit(latitude: Double, longitudeEast: Double) -> (x: Double, y: Double, z: Double) {
        let lat = latitude * Double.pi / 180
        let lon = longitudeEast * Double.pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }
}
