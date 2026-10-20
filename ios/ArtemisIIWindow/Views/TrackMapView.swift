import SwiftUI
import UIKit

struct TrackPlace: Equatable {
    var longitudeEast: Double
    var latitude: Double
    var rangeKm: Double
    var altitudeKm: Double
}

/// The crater map uses the same 340° E–150° E, 48° N–42° S strip as `lroc-track.jpg`.
enum TrackMapGeometry {
    static let lonLeft = 340.0
    static let lonRight = 150.0
    static let latTop = 48.0
    static let latBottom = -42.0

    static func place(sample: PathSample, radiusKm: Double) -> TrackPlace {
        place(x: sample.x, y: sample.y, z: sample.z, rangeKm: sample.rangeKm, radiusKm: radiusKm)
    }

    static func place(at date: Date, samples: [PathSample], radiusKm: Double) -> TrackPlace? {
        guard let xyz = FlybyPath.position(at: date, samples: samples) else { return nil }
        let range = (xyz.x * xyz.x + xyz.y * xyz.y + xyz.z * xyz.z).squareRoot()
        return place(x: xyz.x, y: xyz.y, z: xyz.z, rangeKm: range, radiusKm: radiusKm)
    }

    static func point(lon: Double, lat: Double, in size: CGSize) -> CGPoint {
        var east = lon.truncatingRemainder(dividingBy: 360)
        if east < 0 { east += 360 }
        let x = (lonLeft - east) / (lonLeft - lonRight) * size.width
        let y = (latTop - lat) / (latTop - latBottom) * size.height
        return CGPoint(x: x, y: y)
    }

    static func kilometers(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func place(x: Double, y: Double, z: Double, rangeKm: Double, radiusKm: Double) -> TrackPlace {
        let distance = max(rangeKm, 1)
        var lon = atan2(y, x) * 180 / .pi
        if lon < 0 { lon += 360 }
        let lat = asin(max(-1, min(1, z / distance))) * 180 / .pi
        return TrackPlace(
            longitudeEast: lon,
            latitude: lat,
            rangeKm: rangeKm,
            altitudeKm: rangeKm - radiusKm
        )
    }
}

enum TrackMapImage {
    static func load(in bundle: Bundle = .main) -> UIImage? {
        let url = bundle.url(forResource: "lroc-track", withExtension: "jpg")
            ?? bundle.url(forResource: "lroc-track", withExtension: "jpg", subdirectory: "Resources")
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// SVS LROC crop with the Horizons MOON_ME track. The SVS credit lives in About.
struct TrackMapView: View {
    var date: Date
    var emphasized: String?

    var body: some View {
        let bundled = FlybyEphemeris.bundled
        ZStack(alignment: .topLeading) {
            HybridColor.ground
            if let image = TrackMapImage.load() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            Canvas { context, size in
                guard let bundled else { return }
                let samples = bundled.samples
                let radius = bundled.document.radiusKm
                let approach = FlybyPath.closestApproach(samples, radiusKm: radius)
                var path = Path()
                var drawing = false
                var previous: CGPoint?
                let start = samples.first?.date ?? date
                let end = approach?.date ?? samples.last?.date ?? date
                for sample in samples where sample.date >= start && sample.date <= end {
                    let place = TrackMapGeometry.place(sample: sample, radiusKm: radius)
                    let point = TrackMapGeometry.point(lon: place.longitudeEast, lat: place.latitude, in: size)
                    if let previous, abs(point.x - previous.x) > size.width * 0.45 {
                        context.stroke(path, with: .color(HybridColor.cream.opacity(0.9)), lineWidth: 1.5)
                        path = Path()
                        drawing = false
                    }
                    if drawing {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                        drawing = true
                    }
                    previous = point
                }
                if drawing {
                    context.stroke(path, with: .color(HybridColor.cream.opacity(0.9)), lineWidth: 1.5)
                }
                if let live = TrackMapGeometry.place(at: date, samples: samples, radiusKm: radius) {
                    let point = TrackMapGeometry.point(lon: live.longitudeEast, lat: live.latitude, in: size)
                    let mark = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: mark), with: .color(HybridColor.gold))
                }
                for site in LunarSites.marked {
                    let point = TrackMapGeometry.point(lon: site.longitudeEast, lat: site.latitude, in: size)
                    guard point.x >= -8, point.y >= -8, point.x <= size.width + 8, point.y <= size.height + 8 else { continue }
                    let strong = site.id == emphasized
                    let radius: CGFloat = strong ? 6 : 3.5
                    let mark = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: mark), with: .color(strong ? HybridColor.gold : HybridColor.cream), lineWidth: strong ? 2 : 1)
                }
            }
            if let bundled, let live = TrackMapGeometry.place(
                at: date,
                samples: bundled.samples,
                radiusKm: bundled.document.radiusKm
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ORION")
                        .font(HybridFont.text(9, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(HybridColor.gold)
                    Text("\(TrackMapGeometry.kilometers(live.rangeKm)) km")
                        .font(HybridFont.text(12, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(HybridColor.cream)
                    Text("alt \(TrackMapGeometry.kilometers(live.altitudeKm)) km")
                        .font(HybridFont.text(11, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(HybridColor.dim)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .environment(\.colorScheme, .dark)
                .padding(8)
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mission Control map. Orion’s Horizons track in the MOON_ME frame, with USGS centers for Aristarchus and Reiner Gamma.")
    }
}
