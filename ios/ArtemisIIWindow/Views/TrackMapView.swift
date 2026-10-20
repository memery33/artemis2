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

    static let pixelWidth = 1400.0
    static let pixelHeight = 663.0
    static var aspect: CGFloat { CGFloat(pixelWidth / pixelHeight) }

    /// Size of the 1400×663 strip when it is aspect-fit to `width` points.
    static func fittedSize(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width * pixelHeight / pixelWidth)
    }

    static func normalizedEast(_ lon: Double) -> Double {
        var east = lon.truncatingRemainder(dividingBy: 360)
        if east < 0 { east += 360 }
        return east
    }

    /// Pixel in the unflipped file. The file’s left edge is 340° E, so west sits on the right.
    static func filePixel(lon: Double, lat: Double) -> CGPoint {
        let east = normalizedEast(lon)
        let x = (lonLeft - east) / (lonLeft - lonRight) * pixelWidth
        let y = (latTop - lat) / (latTop - latBottom) * pixelHeight
        return CGPoint(x: x, y: y)
    }

    /// Point in a view that draws the file mirrored, so west is on the left.
    static func point(lon: Double, lat: Double, in size: CGSize) -> CGPoint {
        let file = filePixel(lon: lon, lat: lat)
        let x = (pixelWidth - file.x) / pixelWidth * size.width
        let y = file.y / pixelHeight * size.height
        return CGPoint(x: x, y: y)
    }

    /// Aspect-fill of the 1400×663 strip inside `size`. The image and the markers share this rect.
    static func fillRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = max(size.width / pixelWidth, size.height / pixelHeight)
        let width = pixelWidth * scale
        let height = pixelHeight * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    static func point(lon: Double, lat: Double, in rect: CGRect) -> CGPoint {
        let local = point(lon: lon, lat: lat, in: rect.size)
        return CGPoint(x: rect.minX + local.x, y: rect.minY + local.y)
    }

    /// "A" and "R" sit in the square crater marks. Other sites stay unlabeled dots.
    static func markerLetter(for siteID: String) -> String? {
        switch siteID {
        case "aristarchus": return "A"
        case "reiner-gamma": return "R"
        default: return nil
        }
    }

    enum ReadoutCorner: Equatable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

        func rect(in size: CGSize, box: CGSize, margin: CGFloat) -> CGRect {
            switch self {
            case .topLeading:
                return CGRect(x: margin, y: margin, width: box.width, height: box.height)
            case .topTrailing:
                return CGRect(x: size.width - margin - box.width, y: margin, width: box.width, height: box.height)
            case .bottomLeading:
                return CGRect(x: margin, y: size.height - margin - box.height, width: box.width, height: box.height)
            case .bottomTrailing:
                return CGRect(
                    x: size.width - margin - box.width,
                    y: size.height - margin - box.height,
                    width: box.width,
                    height: box.height
                )
            }
        }

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    /// The ORION box goes in the corner farthest from the projected marks.
    /// The compass already occupies the top-left, so that corner loses unless every other corner is worse.
    static func readoutCorner(
        markers: [CGPoint],
        in size: CGSize,
        box: CGSize = CGSize(width: 124, height: 70),
        margin: CGFloat = 8
    ) -> ReadoutCorner {
        let corners: [ReadoutCorner] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        let compass = CGRect(x: 0, y: 0, width: 54, height: 42)
        func clearance(_ corner: ReadoutCorner) -> CGFloat {
            let rect = corner.rect(in: size, box: box, margin: margin)
            var score = markers.map { distance($0, from: rect) }.min() ?? 10_000
            if rect.intersects(compass) {
                score = min(score, 0)
            }
            return score
        }
        return corners.max { clearance($0) < clearance($1) } ?? .bottomLeading
    }

    static func distance(_ point: CGPoint, from rect: CGRect) -> CGFloat {
        if rect.contains(point) { return 0 }
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
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
        Color.clear
            .aspectRatio(TrackMapGeometry.aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let rect = TrackMapGeometry.fillRect(in: geo.size)
                    let corner = TrackMapGeometry.readoutCorner(
                        markers: markerPoints(bundled: bundled, in: rect),
                        in: geo.size
                    )
                    ZStack {
                        if let image = TrackMapImage.load() {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: rect.width + 2, height: rect.height + 2)
                                .scaleEffect(x: -1, y: 1)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        mapCanvas(bundled: bundled, rect: rect)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(alignment: .topLeading) { compass }
                    .overlay(alignment: corner.alignment) { orionReadout(bundled: bundled) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Crater map. Orion’s Horizons track in the MOON_ME frame, with USGS centers for Aristarchus and Reiner Gamma. North is up and west is left.")
    }

    private func markerPoints(
        bundled: (document: FlybyDocument, samples: [PathSample])?,
        in rect: CGRect
    ) -> [CGPoint] {
        var points = LunarSites.marked.map {
            TrackMapGeometry.point(lon: $0.longitudeEast, lat: $0.latitude, in: rect)
        }
        if let bundled, let live = TrackMapGeometry.place(
            at: date,
            samples: bundled.samples,
            radiusKm: bundled.document.radiusKm
        ) {
            points.append(TrackMapGeometry.point(lon: live.longitudeEast, lat: live.latitude, in: rect))
        }
        return points
    }

    private var compass: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("N ↑")
            Text("W ←")
        }
        .font(HybridFont.text(9, relativeTo: .caption2))
        .foregroundStyle(HybridColor.cream)
        .padding(6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func orionReadout(bundled: (document: FlybyDocument, samples: [PathSample])?) -> some View {
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
            .allowsHitTesting(false)
        }
    }

    private func mapCanvas(bundled: (document: FlybyDocument, samples: [PathSample])?, rect: CGRect) -> some View {
        Canvas { context, _ in
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
                let point = TrackMapGeometry.point(lon: place.longitudeEast, lat: place.latitude, in: rect)
                if let previous, abs(point.x - previous.x) > rect.width * 0.45 {
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
            for site in LunarSites.marked where site.id != emphasized {
                drawSite(site, strong: false, context: &context, rect: rect)
            }
            if let live = TrackMapGeometry.place(at: date, samples: samples, radiusKm: radius) {
                let point = TrackMapGeometry.point(lon: live.longitudeEast, lat: live.latitude, in: rect)
                let mark = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: mark), with: .color(HybridColor.gold))
            }
            if let site = LunarSites.marked.first(where: { $0.id == emphasized }) {
                drawSite(site, strong: true, context: &context, rect: rect)
            }
        }
    }

    private func drawSite(_ site: LunarSite, strong: Bool, context: inout GraphicsContext, rect: CGRect) {
        let point = TrackMapGeometry.point(lon: site.longitudeEast, lat: site.latitude, in: rect)
        guard point.x >= -8, point.y >= -8, point.x <= rect.maxX + 8, point.y <= rect.maxY + 8 else { return }
        let square = TrackMapGeometry.markerLetter(for: site.id) != nil
        let side: CGFloat = strong ? 14 : 11
        let mark = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        let marker = square ? Path(mark) : Path(ellipseIn: mark)
        let color = strong ? HybridColor.gold : HybridColor.cream
        context.stroke(marker, with: .color(color), lineWidth: strong ? 2 : 1)
        if let letter = TrackMapGeometry.markerLetter(for: site.id) {
            let text = context.resolve(
                Text(letter)
                    .font(.system(size: strong ? 9 : 7, weight: .bold))
                    .foregroundStyle(color)
            )
            context.draw(text, at: point, anchor: .center)
        }
    }
}
