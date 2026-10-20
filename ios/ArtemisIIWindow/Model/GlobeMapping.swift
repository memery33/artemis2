import SceneKit

/// The moon node’s +90° yaw about Y puts texture u = 0.5 (longitude 0) on
/// SceneKit +X, which is MOON_ME +X. East increases u and lands on SceneKit −Z.
enum GlobeMapping {
    /// Fraction of the true altitude kept on screen. Direction is not changed.
    static let displayAltitudeScale = 0.05
    /// Moon radii. At a 38° field of view the disk fills most of the panel.
    static let cameraDistance: Float = 3.85

    /// Equirectangular SVS map. u = 0.5 is longitude 0; east increases u.
    static func textureU(longitudeEast: Double) -> Double {
        var lon = longitudeEast.truncatingRemainder(dividingBy: 360)
        if lon > 180 { lon -= 360 }
        if lon <= -180 { lon += 360 }
        return 0.5 + lon / 360
    }

    /// Where that texture coordinate is painted after the +90° yaw.
    static func scene(textureU u: Double, latitude: Double) -> SCNVector3 {
        let longitude = (u - 0.5) * 360
        return scene(MoonFrame.unit(latitude: latitude, longitudeEast: longitude), radiusKm: 1)
    }

    /// Camera on the ray from the Moon’s center through this MOON_ME vector.
    static func cameraPosition(toward me: (x: Double, y: Double, z: Double)) -> SCNVector3 {
        let aimed = scene(me, radiusKm: 1)
        let length = (aimed.x * aimed.x + aimed.y * aimed.y + aimed.z * aimed.z).squareRoot()
        guard length > 0.001 else { return SCNVector3(cameraDistance, 0, 0) }
        return SCNVector3(
            aimed.x / length * cameraDistance,
            aimed.y / length * cameraDistance,
            aimed.z / length * cameraDistance
        )
    }

    /// IAU MOON_ME body-fixed (x at 0° east, y toward 90° east, z north) into SceneKit Y-up.
    /// `compressAltitude` draws a path sample closer than its true range and keeps its direction.
    static func scene(
        _ me: (x: Double, y: Double, z: Double),
        radiusKm: Double,
        compressAltitude: Bool = false
    ) -> SCNVector3 {
        let range = (me.x * me.x + me.y * me.y + me.z * me.z).squareRoot()
        let scale: Double
        if compressAltitude, range > 0, radiusKm > 0 {
            let moons = range / radiusKm
            let display = 1 + max(0, moons - 1) * displayAltitudeScale
            scale = display / range
        } else {
            scale = 1 / max(radiusKm, 0.001)
        }
        return SCNVector3(Float(me.x * scale), Float(me.z * scale), Float(-me.y * scale))
    }
}
