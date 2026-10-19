import SceneKit
import SwiftUI
import UIKit

/// Moon-centered Orion path. Dragging the path seeks the mission clock.
/// The color map is the bundled SVS CGI Moon Kit image, lit evenly because
/// this view is a map, not a reconstruction of the flyby lighting.
struct MoonGlobeView: View {
    @EnvironmentObject private var model: PlaybackModel

    private static let loaded: (document: FlybyDocument, samples: [PathSample])? = {
        guard let document = FlybyEphemeris.load() else { return nil }
        let samples = FlybyEphemeris.samples(in: document)
        guard !samples.isEmpty else { return nil }
        return (document, samples)
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let loaded = Self.loaded {
                let document = loaded.document
                let samples = loaded.samples
                GlobeScene(
                    samples: samples,
                    radiusKm: document.radiusKm,
                    utc: model.utc,
                    milestones: pins,
                    onSeek: { model.seek(to: $0) },
                    onPin: { model.jump(to: $0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("orion-path")
                .accessibilityLabel(accessibilityText(samples: samples, radiusKm: document.radiusKm))
                caption(samples: samples, radiusKm: document.radiusKm)
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

    private func caption(samples: [PathSample], radiusKm: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Orion’s path from JPL Horizons, Moon center, MEAN_ME. Drag the path to move the clock.")
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
        var text = "Orion path from JPL Horizons. Drag to move the mission clock."
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

private struct GlobeScene: UIViewRepresentable {
    var samples: [PathSample]
    var radiusKm: Double
    var utc: Date
    var milestones: [Milestone]
    var onSeek: (Date) -> Void
    var onPin: (Milestone) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSeek: onSeek, onPin: onPin)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.scene = makeScene()
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
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSeek = onSeek
        context.coordinator.onPin = onPin
        context.coordinator.samples = samples
        context.coordinator.milestones = milestones
        context.coordinator.radiusKm = radiusKm
        guard let now = view.scene?.rootNode.childNode(withName: "now", recursively: true),
              let position = FlybyPath.position(at: utc, samples: samples) else {
            return
        }
        now.position = GlobeMapping.scene(position, radiusKm: radiusKm)
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let moon = SCNSphere(radius: 1)
        moon.segmentCount = 96
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "lroc_color_2k")
        material.lightingModel = .constant
        material.isDoubleSided = false
        moon.materials = [material]
        let moonNode = SCNNode(geometry: moon)
        moonNode.name = "moon"
        // The SVS map is centered on 0° longitude. SceneKit shows the image
        // center toward +Z, so yaw it onto the MEAN_ME prime meridian (+X).
        moonNode.eulerAngles.y = -.pi / 2
        scene.rootNode.addChildNode(moonNode)

        var points: [SCNVector3] = []
        points.reserveCapacity(samples.count)
        for sample in samples {
            points.append(GlobeMapping.scene((sample.x, sample.y, sample.z), radiusKm: radiusKm))
        }
        if points.count > 1 {
            let path = lineGeometry(points)
            path.firstMaterial?.diffuse.contents = UIColor.white
            path.firstMaterial?.emission.contents = UIColor(white: 1, alpha: 0.9)
            path.firstMaterial?.lightingModel = .constant
            let pathNode = SCNNode(geometry: path)
            pathNode.name = "path"
            scene.rootNode.addChildNode(pathNode)
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
            let text = SCNText(string: site.label, extrusionDepth: 0)
            text.font = UIFont.systemFont(ofSize: 8, weight: .medium)
            text.flatness = 0.2
            text.firstMaterial?.diffuse.contents = UIColor.white
            text.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: text)
            node.scale = SCNVector3(0.012, 0.012, 0.012)
            node.position = GlobeMapping.scene(unit, radiusKm: 1 / 1.08)
            node.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(node)

            let mark = SCNSphere(radius: 0.02)
            mark.firstMaterial?.diffuse.contents = UIColor.white
            mark.firstMaterial?.lightingModel = .constant
            let markNode = SCNNode(geometry: mark)
            markNode.position = GlobeMapping.scene(unit, radiusKm: 1)
            scene.rootNode.addChildNode(markNode)
        }

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 80
        camera.fieldOfView = 38
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        if let approach = FlybyPath.closestApproach(samples, radiusKm: radiusKm),
           let position = FlybyPath.position(at: approach.date, samples: samples) {
            let placed = GlobeMapping.scene(position, radiusKm: radiusKm)
            let length = max(0.001, simdLength(placed))
            let outward =  length + 6
            cameraNode.position = SCNVector3(
                placed.x / length * outward,
                placed.y / length * outward * 0.35 + 1.2,
                placed.z / length * outward
            )
        } else {
            cameraNode.position = SCNVector3(0, 2, 16)
        }
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        return scene
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
        var onSeek: (Date) -> Void
        var onPin: (Milestone) -> Void
        var samples: [PathSample] = []
        var milestones: [Milestone] = []
        var radiusKm: Double = 1
        weak var view: SCNView?

        init(onSeek: @escaping (Date) -> Void, onPin: @escaping (Milestone) -> Void) {
            self.onSeek = onSeek
            self.onPin = onPin
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            guard let date = nearestSample(to: point, in: view) else { return }
            onSeek(date)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            if let milestone = nearestPin(to: point, in: view, limit: 36) {
                onPin(milestone)
                return
            }
            if let date = nearestSample(to: point, in: view) {
                onSeek(date)
            }
        }

        private func nearestSample(to point: CGPoint, in view: SCNView) -> Date? {
            var best: (date: Date, distance: CGFloat)?
            for sample in samples {
                let projected = view.projectPoint(GlobeMapping.scene((sample.x, sample.y, sample.z), radiusKm: radiusKm))
                let dx = CGFloat(projected.x) - point.x
                let dy = CGFloat(projected.y) - point.y
                let distance = dx * dx + dy * dy
                if best == nil || distance < best!.distance {
                    best = (sample.date, distance)
                }
            }
            return best?.date
        }

        private func nearestPin(to point: CGPoint, in view: SCNView, limit: CGFloat) -> Milestone? {
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
