import Foundation

enum StageMode: Equatable {
    case phone
    case landscape
    case fold
}

/// Open-fold shape. A phone on its side is shorter than this, so it is not the fold.
enum LayoutChoice {
    static func isOpenFold(width: Double, height: Double, regularWidth: Bool) -> Bool {
        guard width > 0, height > 0 else { return false }
        let aspect = width / height
        let wide = regularWidth || width >= 840
        return wide && aspect >= 1.2 && aspect <= 1.6 && height >= 520 && width <= 1200
    }

    /// Fold wins when the shape matches. Otherwise a compact height, or a short
    /// wide aspect, is the landscape phone. A portrait phone stays `.phone`.
    static func stage(
        width: Double,
        height: Double,
        regularWidth: Bool,
        compactHeight: Bool
    ) -> StageMode {
        if width > 0, height > 0, isOpenFold(width: width, height: height, regularWidth: regularWidth) {
            return .fold
        }
        if isLandscapePhone(width: width, height: height, compactHeight: compactHeight) {
            return .landscape
        }
        return .phone
    }

    static func isLandscapePhone(width: Double, height: Double, compactHeight: Bool) -> Bool {
        guard height > 0 else { return false }
        if width > 0, height > 0 {
            if isOpenFold(width: width, height: height, regularWidth: true) { return false }
            if isOpenFold(width: width, height: height, regularWidth: false) { return false }
            if width <= height { return false }
        }
        if compactHeight { return true }
        guard width > 0, height > 0 else { return false }
        return width > height && width / height >= 1.2 && height < 520
    }

    /// Phone and landscape share the 720 frames. Rotation between them does not
    /// change the tier, so the player is not rebuilt.
    static func readsPhoneFrames(_ mode: StageMode) -> Bool {
        mode != .fold
    }
}

/// Geographic targets on the lon 210–330, lat −40–45 plate. Hertzsprung stays off it.
enum MapProjection {
    static let lon0 = 210.0
    static let lon1 = 330.0
    static let lat0 = -40.0
    static let lat1 = 45.0

    static func geographicTargets(_ targets: [MapTarget]) -> [MapTarget] {
        var seen = Set<String>()
        var rows: [MapTarget] = []
        for target in targets where target.geographic {
            if seen.contains(target.name) { continue }
            seen.insert(target.name)
            rows.append(target)
        }
        return rows
    }

    static func point(lon: Double, lat: Double, width: Double, height: Double) -> (x: Double, y: Double)? {
        guard width > 0, height > 0 else { return nil }
        guard lon >= lon0, lon <= lon1, lat >= lat0, lat <= lat1 else { return nil }
        let x = (lon - lon0) / (lon1 - lon0) * width
        let y = (lat1 - lat) / (lat1 - lat0) * height
        return (x, y)
    }

    /// One measured name. `x` and `y` are the dot. `width` and `height` are the text.
    struct LabelAnchor: Equatable, Sendable {
        var name: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    struct LabelBounds: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    /// A name box. `width` stays the measured width when the plate can hold it.
    struct LabelBox: Equatable, Sendable {
        var name: String
        var dotX: Double
        var dotY: Double
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    /// Keep every name inside `bounds`. Boxes do not overlap. A name wider than
    /// the plate shrinks to the plate so the caller can scale it instead of clipping.
    static func placeLabels(_ anchors: [LabelAnchor], in bounds: LabelBounds) -> [LabelBox] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        var seen = Set<String>()
        var items: [LabelAnchor] = []
        for anchor in anchors where !seen.contains(anchor.name) {
            seen.insert(anchor.name)
            items.append(anchor)
        }
        items.sort { lhs, rhs in
            if lhs.x == rhs.x { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }
        let pad = 3.0
        var placed: [LabelBox] = []
        for item in items {
            let fitted = fittedSize(item, in: bounds)
            var chosen: (x: Double, y: Double)?
            for candidate in candidates(for: item, width: fitted.width, height: fitted.height) {
                let box = LabelBox(
                    name: item.name,
                    dotX: item.x,
                    dotY: item.y,
                    x: candidate.x,
                    y: candidate.y,
                    width: fitted.width,
                    height: fitted.height
                )
                if !contains(box, bounds) { continue }
                if placed.allSatisfy({ !overlaps($0, box, pad: pad) }) {
                    chosen = candidate
                    break
                }
            }
            if chosen == nil {
                chosen = gridSearch(
                    item: item,
                    width: fitted.width,
                    height: fitted.height,
                    bounds: bounds,
                    placed: placed,
                    pad: pad
                )
            }
            let origin = chosen ?? clampedOrigin(
                item: item,
                width: fitted.width,
                height: fitted.height,
                bounds: bounds
            )
            placed.append(
                LabelBox(
                    name: item.name,
                    dotX: item.x,
                    dotY: item.y,
                    x: origin.x,
                    y: origin.y,
                    width: fitted.width,
                    height: fitted.height
                )
            )
        }
        return placed
    }

    /// Largest scale in tenths, down to `minimumScale`, whose boxes stay inside
    /// the plate at their scaled size and do not overlap. The last attempt is
    /// still inside the plate when nothing smaller will separate them.
    static func fitLabels(
        _ anchors: [LabelAnchor],
        in bounds: LabelBounds,
        minimumScale: Double = 0.4
    ) -> [LabelBox] {
        let floorStep = max(1, Int((minimumScale * 10).rounded()))
        var last: [LabelBox] = []
        let names = Set(anchors.map(\.name))
        for step in stride(from: 10, through: floorStep, by: -1) {
            let scale = Double(step) / 10
            let scaled = anchors.map { anchor in
                LabelAnchor(
                    name: anchor.name,
                    x: anchor.x,
                    y: anchor.y,
                    width: anchor.width * scale,
                    height: anchor.height * scale
                )
            }
            let boxes = placeLabels(scaled, in: bounds)
            last = boxes
            if boxes.count == names.count, boxesFit(boxes, scaled: scaled, in: bounds) {
                return boxes
            }
        }
        return last
    }

    private static func boxesFit(
        _ boxes: [LabelBox],
        scaled: [LabelAnchor],
        in bounds: LabelBounds
    ) -> Bool {
        guard boxes.allSatisfy({ contains($0, bounds) }) else { return false }
        for box in boxes {
            guard let asked = scaled.first(where: { $0.name == box.name }) else { return false }
            if asked.width <= bounds.width + 0.01, box.width + 0.5 < asked.width { return false }
            if asked.height <= bounds.height + 0.01, box.height + 0.5 < asked.height { return false }
        }
        for index in boxes.indices {
            for other in boxes.indices where other > index {
                if overlaps(boxes[index], boxes[other], pad: 0) { return false }
            }
        }
        return true
    }

    private static func fittedSize(_ item: LabelAnchor, in bounds: LabelBounds) -> (width: Double, height: Double) {
        (min(max(0, item.width), bounds.width), min(max(0, item.height), bounds.height))
    }

    private static func candidates(
        for item: LabelAnchor,
        width: Double,
        height: Double
    ) -> [(x: Double, y: Double)] {
        let x = item.x
        let y = item.y
        var spots: [(Double, Double)] = [
            (x + 6, y - height),
            (x - width - 6, y - height),
            (x - width / 2, y - height - 8),
            (x - width / 2, y + 8),
            (x + 8, y - height * 2 - 8),
            (x + 8, y + height + 4),
            (x - width - 8, y - height * 2 - 8),
            (x - width - 8, y + height + 4),
        ]
        for ring in 1...6 {
            let shift = Double(ring) * (height + 4)
            spots.append((x + 6, y - height - shift))
            spots.append((x + 6, y + shift))
            spots.append((x - width - 6, y - height - shift))
            spots.append((x - width - 6, y + shift))
            spots.append((x + shift, y - height))
            spots.append((x - width - shift, y - height))
        }
        return spots.map { (x: $0.0, y: $0.1) }
    }

    private static func gridSearch(
        item: LabelAnchor,
        width: Double,
        height: Double,
        bounds: LabelBounds,
        placed: [LabelBox],
        pad: Double
    ) -> (x: Double, y: Double)? {
        let step = max(4.0, (height / 2).rounded())
        guard step > 0, width <= bounds.width, height <= bounds.height else { return nil }
        var best: (x: Double, y: Double)?
        var bestDistance = Double.infinity
        var y = bounds.y
        while y + height <= bounds.maxY + 0.01 {
            var x = bounds.x
            while x + width <= bounds.maxX + 0.01 {
                let box = LabelBox(
                    name: item.name,
                    dotX: item.x,
                    dotY: item.y,
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )
                if placed.allSatisfy({ !overlaps($0, box, pad: pad) }) {
                    let distance = hypot(x - item.x, (y + height) - item.y)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = (x, y)
                    }
                }
                x += step
            }
            y += step
        }
        return best
    }

    private static func clampedOrigin(
        item: LabelAnchor,
        width: Double,
        height: Double,
        bounds: LabelBounds
    ) -> (x: Double, y: Double) {
        let x = min(max(bounds.x, item.x), bounds.maxX - width)
        let y = min(max(bounds.y, item.y - height), bounds.maxY - height)
        return (x, y)
    }

    private static func contains(_ box: LabelBox, _ bounds: LabelBounds) -> Bool {
        box.x >= bounds.x - 0.01
            && box.y >= bounds.y - 0.01
            && box.maxX <= bounds.maxX + 0.01
            && box.maxY <= bounds.maxY + 0.01
    }

    private static func overlaps(_ a: LabelBox, _ b: LabelBox, pad: Double) -> Bool {
        a.x < b.maxX + pad && a.maxX + pad > b.x && a.y < b.maxY + pad && a.maxY + pad > b.y
    }
}
