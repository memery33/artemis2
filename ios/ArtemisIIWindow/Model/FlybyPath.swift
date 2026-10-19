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
        guard let first = samples.first, let last = samples.last, let total = lengths.last, total > 0 else {
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
