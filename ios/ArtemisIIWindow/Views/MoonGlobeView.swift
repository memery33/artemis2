import SceneKit
import SwiftUI
import UIKit

/// Bundled SVS LROC color map. It is a loose JPEG in the app resources, not an asset catalog image.
enum MoonMap {
    static func resourceURL(in bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: "lroc_color_2k", withExtension: "jpg") {
            return url
        }
        return bundle.url(forResource: "lroc_color_2k", withExtension: "jpg", subdirectory: "Resources")
    }

    static func image(in bundle: Bundle = .main) -> UIImage? {
        guard let url = resourceURL(in: bundle) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// Moon-centered Orion path. The bright arc is the playable spans; the dim arc is context.
struct MoonGlobeView: View {
    @EnvironmentObject private var model: PlaybackModel
    @StateObject private var labels = GlobeLabels()

    var body: some View {
        if RuntimeHost.isUnitTestHost {
            placeholder
        } else {
            globe
        }
    }

    /// No SceneKit, texture decode, or motion while this process is hosting unit tests.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("orion-path")
            Text("Orion’s path from JPL Horizons, Moon center, body-fixed MOON_ME. The arc is drawn at 5% of its true altitude so it sits around the Moon. Latitude and longitude are unchanged. The dim arc is the rest of that window, past and future. Drag the bright path to move the clock. The key light is the sub-solar point from Horizons quantity 15.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityIdentifier("globe-caption")
        }
    }

    private var globe: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let loaded = FlybyEphemeris.bundled {
                let document = loaded.document
                let samples = loaded.samples
                ZStack {
                    GlobeScene(
                        samples: samples,
                        radiusKm: document.radiusKm,
                        utc: model.utc,
                        milestones: pins,
                        spans: playableSpans,
                        currentSpan: currentSpan,
                        labels: labels,
                        onScrubBegan: { model.beginPathScrub() },
                        onScrub: { model.scrubPath(to: $0) },
                        onScrubEnded: { model.endPathScrub() },
                        onPin: { model.dive(to: $0) }
                    )
                    SiteLabelOverlay(labels: labels)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("orion-path")
                .accessibilityLabel(accessibilityText(samples: samples, radiusKm: document.radiusKm))
                caption(samples: samples, radiusKm: document.radiusKm)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("globe-caption")
            } else {
                Text("The Horizons path was not copied into the app.")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("orion-path")
            }
        }
    }

    private var pins: [Milestone] {
        guard let timeline = model.timeline else { return [] }
        return MilestoneList.derive(timeline)
    }

    private var playableSpans: [PathSpan] {
        guard let timeline = model.timeline else { return [] }
        var spans = [PathSpan(start: timeline.window.start, end: timeline.window.end)]
        if let cab = timeline.cabRun {
            spans.append(PathSpan(start: cab.start, end: cab.end))
        }
        return spans
    }

    private var currentSpan: PathSpan? {
        guard let span = model.activeSpan else { return nil }
        return PathSpan(start: span.start, end: span.end)
    }

    private func caption(samples: [PathSample], radiusKm: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Orion’s path from JPL Horizons, Moon center, body-fixed MOON_ME. The arc is drawn at 5% of its true altitude so it sits around the Moon. Latitude and longitude are unchanged. The dim arc is the rest of that window, past and future. Drag the bright path to move the clock. The key light is the sub-solar point from Horizons quantity 15.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            if let approach = FlybyPath.closestApproach(samples, radiusKm: radiusKm) {
                Text(approachLine(approach))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func accessibilityText(samples: [PathSample], radiusKm: Double) -> String {
        var text = "Orion path from JPL Horizons. The dim arc continues past and future. Drag the bright path to move the mission clock."
        if let approach = FlybyPath.closestApproach(samples, radiusKm: radiusKm) {
            text += " " + approachLine(approach)
        }
        return text
    }

    private func approachLine(_ approach: ClosestApproach) -> String {
        let utc = Self.iso.string(from: approach.date)
        let altitude = String(format: "%.1f", approach.altitudeKm)
        let radius = String(format: "%.1f", approach.radiusKm)
        return "Closest approach \(Stamp.clock(utc)) UTC on \(utc.prefix(10)), \(altitude) km above the \(radius) km radius in the Horizons header."
    }

    @MainActor
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

@MainActor
final class GlobeLabels: ObservableObject {
    struct Site: Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        var anchor: CGPoint
        var label: CGPoint
        var visible: Bool
    }

    @Published var sites: [Site] = []
}

private struct SiteLabelOverlay: View {
    @ObservedObject var labels: GlobeLabels

    var body: some View {
        Canvas { context, _ in
            for site in labels.sites where site.visible {
                var path = Path()
                path.move(to: site.anchor)
                path.addLine(to: site.label)
                context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
        }
        .overlay {
            ForEach(labels.sites.filter(\.visible)) { site in
                Text(site.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    }
                    .position(site.label)
                    .accessibilityLabel(site.title)
            }
        }
    }
}

private struct GlobeScene: UIViewRepresentable {
    var samples: [PathSample]
    var radiusKm: Double
    var utc: Date
    var milestones: [Milestone]
    var spans: [PathSpan]
    var currentSpan: PathSpan?
    var labels: GlobeLabels
    var onScrubBegan: () -> Void
    var onScrub: (Date) -> Void
    var onScrubEnded: () -> Void
    var onPin: (Milestone) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScrubBegan: onScrubBegan,
            onScrub: onScrub,
            onScrubEnded: onScrubEnded,
            onPin: onPin
        )
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.clipsToBounds = true
        view.scene = makeScene()
        attachColorMap(to: view, coordinator: context.coordinator)
        view.allowsCameraControl = false
        view.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        context.coordinator.samples = samples
        context.coordinator.milestones = milestones
        context.coordinator.radiusKm = radiusKm
        context.coordinator.spans = spans
        context.coordinator.currentSpan = currentSpan
        context.coordinator.labels = labels
        context.coordinator.clock = utc
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onScrubBegan = onScrubBegan
        context.coordinator.onScrub = onScrub
        context.coordinator.onScrubEnded = onScrubEnded
        context.coordinator.onPin = onPin
        context.coordinator.samples = samples
        context.coordinator.milestones = milestones
        context.coordinator.radiusKm = radiusKm
        context.coordinator.spans = spans
        context.coordinator.currentSpan = currentSpan
        context.coordinator.labels = labels
        context.coordinator.clock = utc
        attachColorMap(to: view, coordinator: context.coordinator)
        guard let now = view.scene?.rootNode.childNode(withName: "now", recursively: true),
              let position = FlybyPath.position(at: utc, samples: samples) else {
            context.coordinator.refreshLabels(in: view)
            return
        }
        now.position = GlobeMapping.scene(position, radiusKm: radiusKm, compressAltitude: true)
        placeCamera(in: view.scene?.rootNode, toward: position, at: utc)
        context.coordinator.refreshLabels(in: view)
    }

    /// Looks along Orion’s current Moon-fixed direction. The key light is the bundled sub-solar vector, not a camera-relative fill.
    private func placeCamera(in root: SCNNode?, toward me: (x: Double, y: Double, z: Double), at date: Date) {
        guard let root,
              let cameraNode = root.childNode(withName: "camera", recursively: false),
              let sun = root.childNode(withName: "sun", recursively: false) else { return }
        let cameraPosition = GlobeMapping.cameraPosition(toward: me)
        cameraNode.position = cameraPosition
        cameraNode.look(at: SCNVector3(0, 0, 0))
        guard let samples = SolarEphemeris.bundled?.samples,
              let sunME = SolarEphemeris.direction(at: date, samples: samples) else {
            sun.light?.intensity = 0
            return
        }
        let placed = GlobeMapping.scene(sunME, radiusKm: 1)
        let length = max(0.001, simdLength(placed))
        sun.light?.intensity = 1100
        sun.position = SCNVector3(placed.x / length * 8, placed.y / length * 8, placed.z / length * 8)
        sun.look(at: SCNVector3(0, 0, 0))
    }

    /// SceneKit loads a file URL on its own. Assigning a decoded `UIImage` to `diffuse.contents` waits on that loader from the main thread.
    private func attachColorMap(to view: SCNView, coordinator: Coordinator) {
        guard !coordinator.didAttachMap, RuntimeHost.mayDecodeImages, let url = MoonMap.resourceURL() else { return }
        coordinator.didAttachMap = true
        view.scene?.rootNode.childNode(withName: "moon", recursively: false)?
            .geometry?.firstMaterial?.diffuse.contents = url
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        let moon = SCNSphere(radius: 1)
        moon.segmentCount = 96
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.35, alpha: 1)
        material.roughness.contents = 0.92
        material.metalness.contents = 0.0
        material.isDoubleSided = false
        moon.materials = [material]
        let moonNode = SCNNode(geometry: moon)
        moonNode.name = "moon"
        // The SVS map is centered on 0° longitude, east to the right, north up.
        // SceneKit shows that image center toward +Z. A +90° yaw about Y carries
        // +Z onto +X, the IAU MOON_ME prime meridian (0° east). The same yaw
        // carries image east from +X onto -Z, and GlobeMapping puts MOON_ME
        // +Y (90° east) on SceneKit -Z. A -90° yaw would put 0° on -X (180°).
        moonNode.eulerAngles.y = .pi / 2
        scene.rootNode.addChildNode(moonNode)

        let glow = SCNSphere(radius: 1.045)
        glow.segmentCount = 64
        let rim = SCNMaterial()
        rim.lightingModel = .constant
        rim.diffuse.contents = UIColor.clear
        rim.emission.contents = UIColor(red: 0.62, green: 0.78, blue: 1, alpha: 1)
        rim.transparent.contents = UIColor(white: 1, alpha: 1)
        rim.transparencyMode = .rgbZero
        rim.blendMode = .add
        rim.writesToDepthBuffer = false
        rim.isDoubleSided = false
        rim.shaderModifiers = [
            .surface: """
            #pragma body
            float ndotv = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            float fresnel = pow(1.0 - ndotv, 2.6);
            _surface.emission.rgb *= fresnel;
            _surface.transparent.a = fresnel * 0.85;
            """
        ]
        glow.materials = [rim]
        let glowNode = SCNNode(geometry: glow)
        glowNode.name = "atmosphere"
        scene.rootNode.addChildNode(glowNode)

        addStars(to: scene)

        if samples.count > 1 {
            let context = lineGeometry(samples.map { GlobeMapping.scene(($0.x, $0.y, $0.z), radiusKm: radiusKm, compressAltitude: true) })
            context.firstMaterial?.diffuse.contents = UIColor(red: 0.72, green: 0.82, blue: 0.95, alpha: 1)
            context.firstMaterial?.emission.contents = UIColor(red: 0.62, green: 0.74, blue: 0.9, alpha: 1)
            context.firstMaterial?.lightingModel = .constant
            let contextNode = SCNNode(geometry: context)
            contextNode.name = "path"
            scene.rootNode.addChildNode(contextNode)
            // The full Horizons window, past and future, as a readable dim arc. The bright span stays on top.
            for (index, sample) in samples.enumerated() where index % 10 == 0 {
                let dot = SCNSphere(radius: 0.007)
                dot.segmentCount = 8
                dot.firstMaterial?.diffuse.contents = UIColor(red: 0.75, green: 0.84, blue: 0.96, alpha: 1)
                dot.firstMaterial?.emission.contents = UIColor(red: 0.65, green: 0.76, blue: 0.92, alpha: 1)
                dot.firstMaterial?.lightingModel = .constant
                let dotNode = SCNNode(geometry: dot)
                dotNode.name = "path-context"
                dotNode.position = GlobeMapping.scene((sample.x, sample.y, sample.z), radiusKm: radiusKm, compressAltitude: true)
                scene.rootNode.addChildNode(dotNode)
            }

            for span in spans {
                let bright = samples.filter { $0.date >= span.start && $0.date <= span.end }
                guard bright.count > 1 else { continue }
                let geometry = lineGeometry(bright.map { GlobeMapping.scene(($0.x, $0.y, $0.z), radiusKm: radiusKm, compressAltitude: true) })
                geometry.firstMaterial?.diffuse.contents = UIColor(red: 0.82, green: 0.93, blue: 1, alpha: 1)
                geometry.firstMaterial?.emission.contents = UIColor(red: 0.75, green: 0.9, blue: 1, alpha: 1)
                geometry.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: geometry)
                node.name = "path-playable"
                scene.rootNode.addChildNode(node)
            }
        }

        let halo = SCNSphere(radius: 0.026)
        halo.segmentCount = 16
        halo.firstMaterial?.lightingModel = .constant
        halo.firstMaterial?.diffuse.contents = UIColor(white: 1, alpha: 0.16)
        halo.firstMaterial?.emission.contents = UIColor(white: 1, alpha: 0.2)
        halo.firstMaterial?.transparency = 0.28
        halo.firstMaterial?.transparencyMode = .dualLayer
        halo.firstMaterial?.blendMode = .add
        halo.firstMaterial?.writesToDepthBuffer = false
        halo.firstMaterial?.readsFromDepthBuffer = false
        let haloNode = SCNNode(geometry: halo)
        haloNode.name = "now-halo"
        let now = SCNSphere(radius: 0.011)
        now.segmentCount = 12
        now.firstMaterial?.diffuse.contents = UIColor.white
        now.firstMaterial?.emission.contents = UIColor.white
        now.firstMaterial?.lightingModel = .constant
        let nowNode = SCNNode(geometry: now)
        nowNode.name = "now"
        nowNode.addChildNode(haloNode)
        if let position = FlybyPath.position(at: utc, samples: samples) {
            nowNode.position = GlobeMapping.scene(position, radiusKm: radiusKm, compressAltitude: true)
        }
        scene.rootNode.addChildNode(nowNode)

        for milestone in milestones {
            guard let first = samples.first?.date, let last = samples.last?.date,
                  milestone.date >= first, milestone.date <= last,
                  let position = FlybyPath.position(at: milestone.date, samples: samples) else { continue }
            let pin = SCNSphere(radius: 0.045)
            pin.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.45, alpha: 1)
            pin.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.72, blue: 0.35, alpha: 1)
            pin.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: pin)
            node.name = "pin-\(milestone.id)"
            node.position = GlobeMapping.scene(position, radiusKm: radiusKm, compressAltitude: true)
            scene.rootNode.addChildNode(node)
        }

        for site in LunarSites.marked {
            let unit = MoonFrame.unit(latitude: site.latitude, longitudeEast: site.longitudeEast)
            let mark = SCNSphere(radius: 0.018)
            mark.firstMaterial?.diffuse.contents = UIColor.white
            mark.firstMaterial?.emission.contents = UIColor.white
            mark.firstMaterial?.lightingModel = .constant
            let markNode = SCNNode(geometry: mark)
            markNode.name = "site-\(site.id)"
            markNode.position = GlobeMapping.scene(unit, radiusKm: 1)
            scene.rootNode.addChildNode(markNode)
        }

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 80
        camera.fieldOfView = 38
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNNode()
        sun.name = "sun"
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.color = UIColor(white: 1, alpha: 1)
        scene.rootNode.addChildNode(sun)
        let aim = FlybyPath.position(at: utc, samples: samples) ?? (x: 1.0, y: 0.0, z: 0.0)
        placeCamera(in: scene.rootNode, toward: aim, at: utc)

        // Fill so the night side stays readable. It is not a solar measurement; the key light is the Horizons sub-solar vector.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 140
        ambient.light?.color = UIColor(white: 0.55, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        return scene
    }

    /// One point-cloud draw. The seed is fixed so the field does not shimmer between launches.
    private func addStars(to scene: SCNScene) {
        var rng = SplitMix(state: 0x4F72696F6E)
        var points: [SCNVector3] = []
        points.reserveCapacity(160)
        for _ in 0..<160 {
            let theta = Float(rng.next()) * 2 * .pi
            let z = Float(rng.next()) * 2 - 1
            let ring = (1 - z * z).squareRoot()
            let radius = Float(5.4 + rng.next() * 3.2)
            points.append(SCNVector3(ring * cos(theta) * radius, z * radius, ring * sin(theta) * radius))
        }
        let source = SCNGeometrySource(vertices: points)
        let indices = (0..<points.count).map { Int32($0) }
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 2.5
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor.white
        geometry.materials = [material]
        let stars = SCNNode(geometry: geometry)
        stars.name = "stars"
        scene.rootNode.addChildNode(stars)
    }

    private func lineGeometry(_ points: [SCNVector3]) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: points)
        var indices: [Int32] = []
        indices.reserveCapacity((points.count - 1) * 2)
        for index in 0..<(points.count - 1) {
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .line,
            primitiveCount: indices.count / 2,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        return SCNGeometry(sources: [source], elements: [element])
    }

    private func simdLength(_ vector: SCNVector3) -> Float {
        (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
    }
}

private struct SplitMix {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// Shared by the globe and the tests. The moon node’s +90° yaw about Y puts texture
/// u = 0.5 (longitude 0) on SceneKit +X, which is MOON_ME +X. East increases u and
/// lands on SceneKit −Z, which is MOON_ME +Y.
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

    /// Camera on the ray from the Moon’s center through this MOON_ME vector, far enough for the disk to fill the panel.
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

extension GlobeScene {
    @MainActor
    final class Coordinator: NSObject {
        var onScrubBegan: () -> Void
        var onScrub: (Date) -> Void
        var onScrubEnded: () -> Void
        var onPin: (Milestone) -> Void
        var samples: [PathSample] = []
        var milestones: [Milestone] = []
        var spans: [PathSpan] = []
        var currentSpan: PathSpan?
        var radiusKm: Double = 1
        weak var view: SCNView?
        weak var labels: GlobeLabels?
        private var scrubbing = false
        var didAttachMap = false
        private var gestureAnchor: (x: CGFloat, y: CGFloat, date: Date)?
        var clock = Date(timeIntervalSinceReferenceDate: 0)

        init(
            onScrubBegan: @escaping () -> Void,
            onScrub: @escaping (Date) -> Void,
            onScrubEnded: @escaping () -> Void,
            onPin: @escaping (Milestone) -> Void
        ) {
            self.onScrubBegan = onScrubBegan
            self.onScrub = onScrub
            self.onScrubEnded = onScrubEnded
            self.onPin = onPin
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                scrubbing = true
                gestureAnchor = (point.x, point.y, clock)
                onScrubBegan()
            case .changed:
                guard let gestureAnchor else { return }
                if let date = draggedDate(to: point, from: gestureAnchor, in: view) {
                    onScrub(date)
                }
            case .ended, .cancelled, .failed:
                gestureAnchor = nil
                if scrubbing {
                    scrubbing = false
                    onScrubEnded()
                }
            default:
                break
            }
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            if let milestone = nearestPin(to: point, in: view, limit: 36) {
                onPin(milestone)
                return
            }
            let ship = shipPoint(in: view) ?? point
            let anchor = (x: ship.x, y: ship.y, date: clock)
            if let date = draggedDate(to: point, from: anchor, in: view) {
                onScrubBegan()
                onScrub(date)
                onScrubEnded()
            }
        }

        func refreshLabels(in view: SCNView) {
            guard view.bounds.width > 1, view.bounds.height > 1, let labels else { return }
            let center = view.projectPoint(SCNVector3(0, 0, 0))
            guard let camera = view.pointOfView else { return }
            let fov = CGFloat(camera.camera?.fieldOfView ?? 38)
            let halfFov = fov * .pi / 180 / 2
            let cameraDistance = CGFloat((
                camera.presentation.worldPosition.x * camera.presentation.worldPosition.x +
                camera.presentation.worldPosition.y * camera.presentation.worldPosition.y +
                camera.presentation.worldPosition.z * camera.presentation.worldPosition.z
            ).squareRoot())
            guard cameraDistance > 1.05, halfFov > 0.01 else { return }
            let limbAngle = asin(min(1, 1 / cameraDistance))
            let moonRadius = min(view.bounds.width, view.bounds.height) / 2 * tan(limbAngle) / tan(halfFov)
            guard moonRadius > 1 else { return }
            let cameraPosition = camera.presentation.worldPosition
            let cameraLength = (
                cameraPosition.x * cameraPosition.x +
                cameraPosition.y * cameraPosition.y +
                cameraPosition.z * cameraPosition.z
            ).squareRoot()
            guard cameraLength > 0.001 else { return }
            var next: [GlobeLabels.Site] = []
            let bounds = view.bounds.insetBy(dx: 40, dy: 18)
            for site in LunarSites.marked {
                let unit = MoonFrame.unit(latitude: site.latitude, longitudeEast: site.longitudeEast)
                let placed = GlobeMapping.scene(unit, radiusKm: 1)
                let projected = view.projectPoint(placed)
                let anchor = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                let visible = facesCamera(placed, camera: cameraPosition) && projected.z < 1 && bounds.insetBy(dx: -36, dy: -18).contains(anchor)
                var direction = CGVector(dx: anchor.x - CGFloat(center.x), dy: anchor.y - CGFloat(center.y))
                let length = hypot(direction.dx, direction.dy)
                if length < 1 {
                    direction = CGVector(dx: 0, dy: -1)
                } else {
                    direction = CGVector(dx: direction.dx / length, dy: direction.dy / length)
                }
                let fromCenter = hypot(anchor.x - CGFloat(center.x), anchor.y - CGFloat(center.y))
                let nearLimb = fromCenter > moonRadius * 0.82
                let push: CGFloat = nearLimb ? moonRadius + 26 : max(fromCenter + 34, moonRadius * 0.55)
                var label = CGPoint(
                    x: CGFloat(center.x) + direction.dx * push,
                    y: CGFloat(center.y) + direction.dy * push
                )
                if hypot(label.x - CGFloat(center.x), label.y - CGFloat(center.y)) < moonRadius + 20 {
                    label = CGPoint(
                        x: CGFloat(center.x) + direction.dx * (moonRadius + 24),
                        y: CGFloat(center.y) + direction.dy * (moonRadius + 24)
                    )
                }
                label.x = min(max(label.x, bounds.minX), bounds.maxX)
                label.y = min(max(label.y, bounds.minY), bounds.maxY)
                next.append(GlobeLabels.Site(
                    id: site.id,
                    title: site.label,
                    anchor: rounded(anchor),
                    label: rounded(label),
                    visible: visible
                ))
            }
            guard next != labels.sites else { return }
            // updateUIView runs inside the SwiftUI update. Publishing here warns in every UI test.
            let published = labels
            Task { @MainActor in
                guard published.sites != next else { return }
                published.sites = next
            }
        }

        private func rounded(_ point: CGPoint) -> CGPoint {
            CGPoint(x: (point.x * 2).rounded() / 2, y: (point.y * 2).rounded() / 2)
        }

        private func shipPoint(in view: SCNView) -> CGPoint? {
            let grouped = screenSamples(in: view)
            let current = currentSpan ?? spans.first
            guard let current, let samples = grouped[current], samples.count >= 2 else { return nil }
            let date = clock
            if date <= samples[0].date {
                return CGPoint(x: CGFloat(samples[0].x), y: CGFloat(samples[0].y))
            }
            for index in 1..<samples.count {
                let start = samples[index - 1]
                let end = samples[index]
                if date <= end.date {
                    let span = end.date.timeIntervalSince(start.date)
                    let portion = span > 0 ? date.timeIntervalSince(start.date) / span : 0
                    return CGPoint(
                        x: CGFloat(start.x + (end.x - start.x) * portion),
                        y: CGFloat(start.y + (end.y - start.y) * portion)
                    )
                }
            }
            let last = samples[samples.count - 1]
            return CGPoint(x: CGFloat(last.x), y: CGFloat(last.y))
        }

        private func draggedDate(
            to point: CGPoint,
            from anchor: (x: CGFloat, y: CGFloat, date: Date),
            in view: SCNView
        ) -> Date? {
            let grouped = screenSamples(in: view)
            let current = currentSpan ?? spans.first
            guard let current, let samples = grouped[current] else { return nil }
            let others = spans.compactMap { span -> (span: PathSpan, samples: [PathScreenSample])? in
                guard span != current, let rows = grouped[span] else { return nil }
                return (span, rows)
            }
            return PathScrub.drag(
                anchorDate: anchor.date,
                translationX: point.x - anchor.x,
                translationY: point.y - anchor.y,
                fingerX: point.x,
                fingerY: point.y,
                current: (current, samples),
                others: others
            )?.date
        }

        private func screenSamples(in view: SCNView) -> [PathSpan: [PathScreenSample]] {
            let camera = view.pointOfView?.presentation.worldPosition
            var grouped: [PathSpan: [PathScreenSample]] = [:]
            for span in spans {
                var rows: [PathScreenSample] = []
                for sample in samples where sample.date >= span.start && sample.date <= span.end {
                    let position = GlobeMapping.scene((sample.x, sample.y, sample.z), radiusKm: radiusKm, compressAltitude: true)
                    let projected = view.projectPoint(position)
                    if let camera, (projected.z >= 1 || !facesCamera(position, camera: camera)) {
                        continue
                    }
                    rows.append(PathScreenSample(date: sample.date, x: Double(projected.x), y: Double(projected.y)))
                }
                grouped[span] = rows
            }
            return grouped
        }

        /// Same hemisphere test as the site labels: the direction from the Moon center toward the sample, against the camera.
        private func facesCamera(_ position: SCNVector3, camera: SCNVector3) -> Bool {
            let cameraLength = (camera.x * camera.x + camera.y * camera.y + camera.z * camera.z).squareRoot()
            let sampleLength = (position.x * position.x + position.y * position.y + position.z * position.z).squareRoot()
            guard cameraLength > 0.001, sampleLength > 0.001 else { return false }
            let facing = (
                position.x * camera.x +
                position.y * camera.y +
                position.z * camera.z
            ) / (cameraLength * sampleLength)
            return facing > 0.2
        }

        private func nearestPin(to point: CGPoint, in view: SCNView, limit: CGFloat) -> Milestone? {
            let current = milestones.filter { milestone in
                guard let span = currentSpan else { return true }
                return milestone.date >= span.start && milestone.date <= span.end
            }
            if let hit = closestPin(in: current, to: point, in: view, limit: limit) {
                return hit
            }
            let others = milestones.filter { milestone in
                guard let span = currentSpan else { return false }
                return milestone.date < span.start || milestone.date > span.end
            }
            return closestPin(in: others, to: point, in: view, limit: min(limit, PathScrub.reach))
        }

        private func closestPin(
            in milestones: [Milestone],
            to point: CGPoint,
            in view: SCNView,
            limit: CGFloat
        ) -> Milestone? {
            let camera = view.pointOfView?.presentation.worldPosition
            var best: (milestone: Milestone, distance: CGFloat)?
            for milestone in milestones {
                guard let position = FlybyPath.position(at: milestone.date, samples: samples) else { continue }
                let placed = GlobeMapping.scene(position, radiusKm: radiusKm, compressAltitude: true)
                let projected = view.projectPoint(placed)
                if let camera, (projected.z >= 1 || !facesCamera(placed, camera: camera)) {
                    continue
                }
                let dx = CGFloat(projected.x) - point.x
                let dy = CGFloat(projected.y) - point.y
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance <= limit, best == nil || distance < best!.distance {
                    best = (milestone, distance)
                }
            }
            return best?.milestone
        }
    }
}
