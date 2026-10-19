import ImageIO
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

    /// Decodes off the main thread. The unit-test host never starts this work.
    static func load(completion: @escaping @MainActor (UIImage?) -> Void) {
        guard !RuntimeHost.isUnitTestHost else { return }
        let url = resourceURL()
        Task.detached(priority: .userInitiated) {
            let owned = url.flatMap { decoded($0) }
            await MainActor.run {
                completion(owned.map { UIImage(cgImage: $0.image) })
            }
        }
    }

    private struct Decoded: @unchecked Sendable {
        var image: CGImage
    }

    private static func decoded(_ url: URL) -> Decoded? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            return nil
        }
        return Decoded(image: image)
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
            Text("Orion’s path from JPL Horizons, Moon center, MEAN_ME. Drag the bright path to move the clock.")
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
            Text("Orion’s path from JPL Horizons, Moon center, MEAN_ME. Drag the bright path to move the clock.")
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
        var text = "Orion path from JPL Horizons. Drag the bright path to move the mission clock."
        if let approach = FlybyPath.closestApproach(samples, radiusKm: radiusKm) {
            text += " " + approachLine(approach)
        }
        return text
    }

    private func approachLine(_ approach: ClosestApproach) -> String {
        let utc = iso(approach.date)
        let altitude = String(format: "%.1f", approach.altitudeKm)
        let radius = String(format: "%.1f", approach.radiusKm)
        return "Closest approach \(Stamp.clock(utc)) UTC on \(utc.prefix(10)), \(altitude) km above the \(radius) km radius in the Horizons header."
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
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
        let sceneView = view
        MoonMap.load { image in
            guard let image,
                  let moon = sceneView.scene?.rootNode.childNode(withName: "moon", recursively: false) else {
                return
            }
            moon.geometry?.firstMaterial?.diffuse.contents = image
        }
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
        guard let now = view.scene?.rootNode.childNode(withName: "now", recursively: true),
              let position = FlybyPath.position(at: utc, samples: samples) else {
            context.coordinator.refreshLabels(in: view)
            return
        }
        now.position = GlobeMapping.scene(position, radiusKm: radiusKm)
        context.coordinator.refreshLabels(in: view)
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
        // The SVS map is centered on 0° longitude. SceneKit shows the image
        // center toward +Z, so yaw it onto the MEAN_ME prime meridian (+X).
        moonNode.eulerAngles.y = -.pi / 2
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
            let context = lineGeometry(samples.map { GlobeMapping.scene(($0.x, $0.y, $0.z), radiusKm: radiusKm) })
            context.firstMaterial?.diffuse.contents = UIColor(white: 0.42, alpha: 1)
            context.firstMaterial?.emission.contents = UIColor(white: 0.28, alpha: 1)
            context.firstMaterial?.lightingModel = .constant
            let contextNode = SCNNode(geometry: context)
            contextNode.name = "path"
            scene.rootNode.addChildNode(contextNode)

            for span in spans {
                let bright = samples.filter { $0.date >= span.start && $0.date <= span.end }
                guard bright.count > 1 else { continue }
                let geometry = lineGeometry(bright.map { GlobeMapping.scene(($0.x, $0.y, $0.z), radiusKm: radiusKm) })
                geometry.firstMaterial?.diffuse.contents = UIColor(red: 0.82, green: 0.93, blue: 1, alpha: 1)
                geometry.firstMaterial?.emission.contents = UIColor(red: 0.75, green: 0.9, blue: 1, alpha: 1)
                geometry.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: geometry)
                node.name = "path-playable"
                scene.rootNode.addChildNode(node)
            }
        }

        let now = SCNSphere(radius: 0.08)
        now.firstMaterial?.diffuse.contents = UIColor.white
        now.firstMaterial?.emission.contents = UIColor.white
        now.firstMaterial?.lightingModel = .constant
        let nowNode = SCNNode(geometry: now)
        nowNode.name = "now"
        if let position = FlybyPath.position(at: utc, samples: samples) {
            nowNode.position = GlobeMapping.scene(position, radiusKm: radiusKm)
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
            node.position = GlobeMapping.scene(position, radiusKm: radiusKm)
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
        camera.zFar = 200
        camera.fieldOfView = 38
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"
        var cameraPosition = SCNVector3(0, 2, 16)
        if let approach = FlybyPath.closestApproach(samples, radiusKm: radiusKm),
           let position = FlybyPath.position(at: approach.date, samples: samples) {
            let placed = GlobeMapping.scene(position, radiusKm: radiusKm)
            let length = max(0.001, simdLength(placed))
            let outward: Float = length + 6
            cameraPosition = SCNVector3(
                placed.x / length * outward,
                placed.y / length * outward * 0.35 + 1.2,
                placed.z / length * outward
            )
        }
        cameraNode.position = cameraPosition
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.color = UIColor(white: 1, alpha: 1)
        let side = cross(cameraPosition, SCNVector3(0, 1, 0))
        let sideLength = max(0.001, simdLength(side))
        sun.position = SCNVector3(side.x / sideLength * 8, 3.2, side.z / sideLength * 8)
        sun.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 140
        ambient.light?.color = UIColor(white: 0.55, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        return scene
    }

    /// Unnamed points. The seed is fixed so the field does not shimmer between launches.
    private func addStars(to scene: SCNScene) {
        var rng = SplitMix(state: 0x4F72696F6E)
        let stars = SCNNode()
        stars.name = "stars"
        for _ in 0..<160 {
            let theta = Float(rng.next()) * 2 * .pi
            let z = Float(rng.next()) * 2 - 1
            let ring = (1 - z * z).squareRoot()
            let radius = Float(18 + rng.next() * 16)
            let point = SCNVector3(ring * cos(theta) * radius, z * radius, ring * sin(theta) * radius)
            let star = SCNSphere(radius: CGFloat(0.012 + rng.next() * 0.02))
            let material = SCNMaterial()
            material.lightingModel = .constant
            let shade = CGFloat(0.75 + rng.next() * 0.25)
            material.diffuse.contents = UIColor(white: shade, alpha: 1)
            material.emission.contents = UIColor(white: shade, alpha: 1)
            star.materials = [material]
            let node = SCNNode(geometry: star)
            node.position = point
            stars.addChildNode(node)
        }
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

    private func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }
}

private struct SplitMix {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

private enum GlobeMapping {
    /// MEAN_ME (x, y east, z north) into SceneKit Y-up.
    static func scene(_ me: (x: Double, y: Double, z: Double), radiusKm: Double) -> SCNVector3 {
        let scale = 1 / radiusKm
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
                let facing = (
                    placed.x * cameraPosition.x +
                    placed.y * cameraPosition.y +
                    placed.z * cameraPosition.z
                ) / cameraLength
                let projected = view.projectPoint(placed)
                let anchor = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                let visible = facing > 0.2 && projected.z < 1 && bounds.insetBy(dx: -36, dy: -18).contains(anchor)
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
            var grouped: [PathSpan: [PathScreenSample]] = [:]
            for span in spans {
                var rows: [PathScreenSample] = []
                for sample in samples where sample.date >= span.start && sample.date <= span.end {
                    let projected = view.projectPoint(GlobeMapping.scene((sample.x, sample.y, sample.z), radiusKm: radiusKm))
                    rows.append(PathScreenSample(date: sample.date, x: Double(projected.x), y: Double(projected.y)))
                }
                grouped[span] = rows
            }
            return grouped
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
            var best: (milestone: Milestone, distance: CGFloat)?
            for milestone in milestones {
                guard let position = FlybyPath.position(at: milestone.date, samples: samples) else { continue }
                let projected = view.projectPoint(GlobeMapping.scene(position, radiusKm: radiusKm))
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
