import Foundation

/// Parsed `demo/data/timeline.json`. UTC strings are kept as shipped.
struct Timeline: Decodable {
    static let cabinID = "art002e016183"

    let version: Int
    let window: TimeSpan
    let pointing: Pointing
    let attribution: Attribution
    let segments: [Segment]
    let lines: [TranscriptLine]
    let frames: [Frame]
    let targets: [MapTarget]
    let crew: [CrewMember]
    let cabRun: TimeSpan?
    let licenses: [LicenseNote]
    let missionStart: MissionStart

    var epoch: Date { missionStart.date }

    enum CodingKeys: String, CodingKey {
        case version, window, pointing, attribution, segments, lines, frames, targets, crew, licenses
        case cabRun = "cab_run"
        case missionStart = "mission_start"
    }

    init(data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(Timeline.self, from: data)
    }
}

struct TimeSpan: Decodable, Equatable {
    let startUTC: String
    let endUTC: String
    let start: Date
    let end: Date
    let label: String
    /// Cab-run note, when the span has one. The flyby window has none.
    let note: String?

    enum CodingKeys: String, CodingKey {
        case start, end, label, note
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        startUTC = try raw.decode(String.self, forKey: .start)
        endUTC = try raw.decode(String.self, forKey: .end)
        label = try raw.decode(String.self, forKey: .label)
        note = try raw.decodeIfPresent(String.self, forKey: .note)
        start = try ISO8601.parse(startUTC)
        end = try ISO8601.parse(endUTC)
    }
}

struct Pointing: Decodable, Equatable {
    let available: Bool
    let provider: String
    let note: String
}

struct Attribution: Decodable, Equatable {
    let credit: String
    let endorsement: String
}

struct MissionStart: Decodable, Equatable {
    let utc: String
    let source: String
    let date: Date

    enum CodingKeys: String, CodingKey {
        case utc, source
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        utc = try raw.decode(String.self, forKey: .utc)
        source = try raw.decode(String.self, forKey: .source)
        date = try ISO8601.parse(utc)
    }
}

struct Segment: Decodable, Equatable, Identifiable {
    let nasaID: String
    let track: String
    let startUTC: String
    let endUTC: String
    let start: Date
    let end: Date
    let file: String
    let targetID: String

    var id: String { nasaID }

    enum CodingKeys: String, CodingKey {
        case nasaID = "nasa_id"
        case track, start, end, file
        case targetID = "target_id"
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        nasaID = try raw.decode(String.self, forKey: .nasaID)
        track = try raw.decode(String.self, forKey: .track)
        startUTC = try raw.decode(String.self, forKey: .start)
        endUTC = try raw.decode(String.self, forKey: .end)
        file = try raw.decode(String.self, forKey: .file)
        targetID = try raw.decodeIfPresent(String.self, forKey: .targetID) ?? ""
        start = try ISO8601.parse(startUTC)
        end = try ISO8601.parse(endUTC)
    }
}

struct TranscriptLine: Decodable, Equatable, Identifiable {
    let utc: String
    let date: Date
    let speaker: String
    let text: String
    let track: String
    let nasaID: String

    var id: String { "\(track)|\(utc)|\(text)" }

    enum CodingKeys: String, CodingKey {
        case utc, speaker, text, track
        case nasaID = "nasa_id"
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        utc = try raw.decode(String.self, forKey: .utc)
        speaker = try raw.decode(String.self, forKey: .speaker)
        text = try raw.decode(String.self, forKey: .text)
        track = try raw.decode(String.self, forKey: .track)
        nasaID = try raw.decode(String.self, forKey: .nasaID)
        date = try ISO8601.parse(utc)
    }
}

struct Frame: Decodable, Equatable, Identifiable {
    let utc: String
    let date: Date
    let nasaID: String
    let instrument: String
    let window: String?
    let cameraLabel: String
    let file: String
    let credit: String
    let look: String?
    let targetID: String
    let exposureNote: String
    let focalLengthMM: Double?
    /// Brightness centroid of the lit surface, 0...1. Nil keeps the default crop.
    let focusX: Double?
    let focusY: Double?

    var id: String { nasaID }
    var isCabinCard: Bool { nasaID == Timeline.cabinID }

    enum CodingKeys: String, CodingKey {
        case utc
        case nasaID = "nasa_id"
        case instrument, window, file, credit, look
        case cameraLabel = "camera_label"
        case targetID = "target_id"
        case exposureNote = "exposure_note"
        case focalLengthMM = "focal_length_mm"
        case focusX = "focus_x"
        case focusY = "focus_y"
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        utc = try raw.decode(String.self, forKey: .utc)
        nasaID = try raw.decode(String.self, forKey: .nasaID)
        instrument = try raw.decode(String.self, forKey: .instrument)
        window = try raw.decodeIfPresent(String.self, forKey: .window)
        cameraLabel = try raw.decode(String.self, forKey: .cameraLabel)
        file = try raw.decode(String.self, forKey: .file)
        credit = try raw.decode(String.self, forKey: .credit)
        look = try raw.decodeIfPresent(String.self, forKey: .look)
        targetID = try raw.decodeIfPresent(String.self, forKey: .targetID) ?? ""
        exposureNote = try raw.decodeIfPresent(String.self, forKey: .exposureNote) ?? ""
        focalLengthMM = try raw.decodeIfPresent(Double.self, forKey: .focalLengthMM)
        focusX = try raw.decodeIfPresent(Double.self, forKey: .focusX)
        focusY = try raw.decodeIfPresent(Double.self, forKey: .focusY)
        date = try ISO8601.parse(utc)
    }
}

struct MapTarget: Decodable, Equatable, Identifiable {
    let name: String
    let lat: Double
    let lon: Double
    let geographic: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, lat, lon, geographic
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: CodingKeys.self)
        name = try raw.decode(String.self, forKey: .name)
        lat = try raw.decode(Double.self, forKey: .lat)
        lon = try raw.decode(Double.self, forKey: .lon)
        geographic = try raw.decodeIfPresent(Bool.self, forKey: .geographic) ?? false
    }
}

struct CrewMember: Decodable, Equatable, Identifiable {
    let id: String
    let track: String
}

struct LicenseNote: Decodable, Equatable, Identifiable {
    let id: String
    let bundle: String
    let doi: String
    let shipped: Bool
    let credit: String
    let usage: String
}

enum ISO8601 {
    static func parse(_ string: String) throws -> Date {
        if let date = date(from: string, fractional: true) ?? date(from: string, fractional: false) {
            return date
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Bad UTC \(string)")
        )
    }

    /// A fresh formatter per call. ISO8601DateFormatter is not Sendable, so it is not stored statically.
    private static func date(from string: String, fractional: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
