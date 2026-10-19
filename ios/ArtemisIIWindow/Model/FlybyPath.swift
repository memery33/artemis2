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

    /// Time and altitude of closest approach from the tabulated geometric ranges.
    ///
    /// The vertex of the parabola through the lowest sample and its two neighbors
    /// is the refined instant. Altitude is that range minus the radius in the
    /// Horizons header, which the caller passes in from the file.
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
        let date = sample.date.addingTimeInterval(vertex * 60)
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

    /// True only in the second around the derived closest-approach time.
    static func fadesInterface(at date: Date, approach: Date) -> Bool {
        abs(date.timeIntervalSince(approach)) < 1
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
    /// The finger has to be this close, in points, to a different bright segment before the clock leaves the current span.
    static let reach: Double = 24

    static func contains(_ date: Date, spans: [PathSpan]) -> Bool {
        spans.contains { date >= $0.start && date <= $0.end }
    }

    /// Maps the finger along the current bright segment.
    /// Another span is used only when the finger is actually on that segment and closer to it.
    static func scrub(
        x: Double,
        y: Double,
        current: (span: PathSpan, samples: [PathScreenSample]),
        others: [(span: PathSpan, samples: [PathScreenSample])]
    ) -> PathScrubChoice? {
        guard let here = project(x: x, y: y, samples: current.samples) else { return nil }
        let reached = others.compactMap { other -> (span: PathSpan, hit: Projection)? in
            guard let hit = project(x: x, y: y, samples: other.samples) else { return nil }
            guard hit.distance <= reach, hit.distance + 1 < here.distance else { return nil }
            return (other.span, hit)
        }.min { $0.hit.distance < $1.hit.distance }
        if let reached {
            return PathScrubChoice(date: reached.hit.date, span: reached.span)
        }
        return PathScrubChoice(date: here.date, span: current.span)
    }

    /// Closest point on the polyline. The date is interpolated along that segment, not snapped to a distant vertex.
    static func project(x: Double, y: Double, samples: [PathScreenSample]) -> Projection? {
        guard samples.count >= 2 else { return nil }
        var best = Projection(date: samples[0].date, distance: .greatestFiniteMagnitude)
        var found = false
        for index in 1..<samples.count {
            let start = samples[index - 1]
            let end = samples[index]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let t: Double
            if lengthSquared > 0 {
                t = min(1, max(0, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
            } else {
                t = 0
            }
            let px = start.x + dx * t
            let py = start.y + dy * t
            let distance = ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot()
            if !found || distance < best.distance {
                let interval = end.date.timeIntervalSince(start.date)
                best = Projection(
                    date: start.date.addingTimeInterval(interval * t),
                    distance: distance
                )
                found = true
            }
        }
        return found ? best : nil
    }

    struct Projection: Equatable, Sendable {
        var date: Date
        var distance: Double
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
        if let hit = clips.first(where: { date >= $0.start && date < $0.end }) {
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

/// IAU names placed on the MEAN_ME globe. Coordinates are planetographic,
/// east-positive, from the USGS Gazetteer of Planetary Nomenclature.
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

enum MoonFrame {
    /// MEAN_ME axes from the Horizons header: +X at east-longitude 0, +Y toward 90° east, +Z north.
    static func unit(latitude: Double, longitudeEast: Double) -> (x: Double, y: Double, z: Double) {
        let lat = latitude * Double.pi / 180
        let lon = longitudeEast * Double.pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }
}
