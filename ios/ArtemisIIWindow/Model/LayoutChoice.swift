import Foundation

/// Open-fold shape. A phone on its side is short, so it stays on the phone layout.
enum LayoutChoice {
    static func isOpenFold(width: Double, height: Double, regularWidth: Bool) -> Bool {
        guard width > 0, height > 0 else { return false }
        let aspect = width / height
        let wide = regularWidth || width >= 840
        return wide && aspect >= 1.2 && aspect <= 1.6 && height >= 520 && width <= 1200
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
}
