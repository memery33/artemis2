import SwiftUI

struct WindowPane: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var turn: Double = 0

    private var side: WindowSide { model.window }

    var body: some View {
        let pair = model.pair(for: side)
        let mix = shownMix(pair)
        let progress = holdProgress(pair)
        Color.clear
            .aspectRatio(side == .nikon ? 1.58 : 4.0 / 3.0, contentMode: .fit)
            .overlay {
                glass(pair: pair, mix: mix, progress: progress)
            }
            .clipShape(RoundedRectangle(cornerRadius: side == .nikon ? 36 : 4, style: .continuous))
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : turn * 24),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.45
            )
            .offset(x: reduceMotion ? 0 : turn * 28)
            .gesture(swipe)
            .onChange(of: model.window) { _, newSide in
                guard !reduceMotion else { return }
                turn = newSide == .cab ? 1 : -1
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.35)) {
                        turn = 0
                    }
                }
            }
            .accessibilityLabel(side == .nikon ? "Window 2, Nikon" : "Window 3, Cab Cam")
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            let dx = value.translation.width
            let dy = value.translation.height
            guard abs(dx) > 48, abs(dx) > abs(dy) else { return }
            model.setWindow(dx < 0 ? .cab : .nikon)
        }
    }

    private func glass(pair: FramePair, mix: Double, progress: Double) -> some View {
        GeometryReader { geo in
            let pixels = max(geo.size.width, geo.size.height) * displayScale * 1.15
            ZStack {
                Color.black
                if let frame = pair.current, let image = model.photo(frame, maxPixel: pixels) {
                    placed(
                        image,
                        motion: motion(progress: progress, index: pair.index),
                        size: geo.size
                    )
                    .opacity(1 - mix)
                }
                if mix > 0, let frame = pair.next, let image = model.photo(frame, maxPixel: pixels) {
                    placed(
                        image,
                        motion: motion(progress: 0, index: pair.index + 1),
                        size: geo.size
                    )
                    .opacity(mix)
                }
                if pair.current == nil && mix == 0 {
                    Text(emptyCopy(pair))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(24)
                }
                subtitle
                if side == .nikon {
                    bezel
                }
            }
            .task(id: framePrefetchToken(pair, pixels: pixels, small: model.phoneImages)) {
                if let frame = pair.current {
                    model.prefetch(frame, maxPixel: pixels)
                }
                if let frame = pair.next {
                    model.prefetch(frame, maxPixel: pixels)
                }
            }
        }
    }

    private var bezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color(red: 0.72, green: 0.72, blue: 0.72), lineWidth: 12)
                .padding(3)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.9), lineWidth: 7)
                .padding(14)
        }
        .allowsHitTesting(false)
    }

    private var subtitle: some View {
        VStack {
            Spacer()
            if let line = model.subtitleLine() {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.speaker)
                        .font(.caption.weight(.semibold))
                    Text(line.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.55))
                .padding(.horizontal, side == .nikon ? 18 : 6)
                .padding(.bottom, side == .nikon ? 20 : 6)
            }
        }
        .allowsHitTesting(false)
    }

    private func emptyCopy(_ pair: FramePair) -> String {
        if side == .cab {
            return "No Cab Cam frame was taken at this time. Times are not shifted to fill the gap."
        }
        if pair.next == nil {
            return "No Window 2 frame at this clock. The last matching picture was not moved."
        }
        return "No Window 2 frame was taken at this time."
    }

    private func shownMix(_ pair: FramePair) -> Double {
        guard !reduceMotion, let current = pair.current, let next = pair.next else { return 0 }
        return FrameSelection.crossfade(now: model.utc, current: current.date, next: next.date).mix
    }

    private func holdProgress(_ pair: FramePair) -> Double {
        guard let current = pair.current else { return 0 }
        return FrameSelection.holdProgress(now: model.utc, current: current.date, next: pair.next?.date)
    }

    /// Window 2 scale is 1.06 + progress × 0.05. Window 3 scale change stays within 4%.
    private func motion(progress: Double, index: Int) -> (scale: CGFloat, x: CGFloat, y: CGFloat) {
        if reduceMotion { return (1, 0, 0) }
        let p = CGFloat(min(1, max(0, progress)))
        let sign: CGFloat = index % 2 == 0 ? -1 : 1
        if side == .cab {
            return (1.025 + p * 0.035, sign * p * 0.65, p * 0.3)
        }
        return (1.06 + p * 0.05, sign * p * 1.1, p * 0.4)
    }

    private func placed(_ image: UIImage, motion: (scale: CGFloat, x: CGFloat, y: CGFloat), size: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(motion.scale)
            .offset(x: size.width * motion.x / 100, y: size.height * motion.y / 100)
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

struct FrameCaption: View {
    @EnvironmentObject private var model: PlaybackModel
    let side: WindowSide

    var body: some View {
        let pair = model.pair(for: side)
        VStack(alignment: .leading, spacing: 4) {
            if let frame = dominant(pair) {
                Text(frame.credit)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                if side == .cab {
                    Text(cabNote(frame))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dominant(_ pair: FramePair) -> Frame? {
        guard let current = pair.current else { return nil }
        guard let next = pair.next else { return current }
        let fade = FrameSelection.crossfade(now: model.utc, current: current.date, next: next.date)
        return fade.dominantIsNext ? next : current
    }

    private func cabNote(_ frame: Frame) -> String {
        var parts = ["Taken \(Stamp.clock(frame.utc)) UTC · \(frame.nasaID)."]
        if frame.look == "dark" {
            parts.append("Real GoPro exposure, nearly black. Not brightened.")
        } else {
            parts.append("Shown as photographed.")
        }
        if model.utc.timeIntervalSince(frame.date) > 45 {
            parts.append("This frame was not moved to match the clock.")
        }
        return parts.joined(separator: " ")
    }
}

struct CompanionPane: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.displayScale) private var displayScale

    private var side: WindowSide { model.window == .nikon ? .cab : .nikon }

    var body: some View {
        let pair = model.pair(for: side)
        Button(action: { model.setWindow(side) }) {
            VStack(alignment: .leading, spacing: 6) {
                Color.black
                    .aspectRatio(side == .cab ? 4.0 / 3.0 : 1.5, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            let pixels = max(geo.size.width, geo.size.height) * displayScale
                            ZStack {
                                if let frame = pair.current,
                                   let image = model.photo(frame, maxPixel: pixels) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                }
                            }
                            .task(id: framePrefetchToken(pair, pixels: pixels, small: model.phoneImages)) {
                                if let frame = pair.current {
                                    model.prefetch(frame, maxPixel: pixels)
                                }
                                if let frame = pair.next {
                                    model.prefetch(frame, maxPixel: pixels)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(caption(pair))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(side == .cab ? "Show Window 3" : "Show Window 2")
    }

    private func caption(_ pair: FramePair) -> String {
        let label = side == .cab ? "Window 3 · Cab Cam" : "Window 2 · Nikon"
        guard let frame = pair.current else {
            if side == .nikon, let frames = model.timeline?.frames {
                let rows = FrameSelection.frames(frames, window: .nikon)
                if let last = rows.last, model.utc > last.date {
                    return "\(label). No frame at this clock. The last matching picture was not moved."
                }
            }
            return "\(label). No frame was taken at this time."
        }
        let taken = "\(label). Taken \(Stamp.clock(frame.utc)) UTC."
        if side == .cab, model.utc.timeIntervalSince(frame.date) > 45 {
            return "\(taken) Not moved to match the clock."
        }
        return taken
    }
}

struct CabinCard: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.displayScale) private var displayScale
    let height: CGFloat

    var body: some View {
        if let frames = model.timeline?.frames,
           let card = FrameSelection.cabinCard(at: model.utc, frames: frames) {
            VStack(alignment: .leading, spacing: 4) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay {
                        GeometryReader { geo in
                            let pixels = max(geo.size.width, geo.size.height) * displayScale
                            ZStack {
                                if let image = model.photo(card, maxPixel: pixels) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                }
                            }
                            .task(id: "\(model.phoneImages)|\(card.file)@\(MediaStore.pixelBucket(pixels))") {
                                model.prefetch(card, maxPixel: pixels)
                            }
                        }
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Cabin · \(card.nasaID) · \(Stamp.clock(card.utc)) UTC")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Not shown through the glass.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct ClockReadout: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        let clocks = ClockMath.format(date: model.utc, epoch: model.timeline?.epoch ?? model.utc)
        HStack(spacing: 8) {
            Text(clocks.utc)
            Spacer(minLength: 4)
            Text(clocks.eastern)
            Spacer(minLength: 4)
            Text(clocks.met)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

struct CreditLine: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        Text(model.timeline?.attribution.credit ?? "Credit: NASA/Artemis II Crew")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusLines: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.engineFailed {
                Text("Audio engine did not start. No substitute sound is played.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            } else if model.segment(at: model.utc) == nil {
                Text("No recording at this time.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if model.range == .cab, let note = model.activeSpan?.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TargetMap: View {
    @EnvironmentObject private var model: PlaybackModel

    var body: some View {
        let targets = MapProjection.geographicTargets(model.timeline?.targets ?? [])
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                var placed: [CGPoint] = []
                for target in targets {
                    guard let raw = MapProjection.point(
                        lon: target.lon,
                        lat: target.lat,
                        width: Double(size.width),
                        height: Double(size.height - 8)
                    ) else { continue }
                    let x = CGFloat(raw.x)
                    var y = CGFloat(raw.y)
                    for prior in placed where abs(prior.x - x) < 90 && abs(prior.y - y) < 13 {
                        y = prior.y + 13
                    }
                    let dot = CGPoint(x: x, y: y)
                    placed.append(dot)
                    let mark = CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5)
                    context.fill(Path(ellipseIn: mark), with: .color(.white))
                    context.draw(
                        Text(target.name).font(.system(size: 9)).foregroundStyle(.white),
                        at: CGPoint(x: dot.x + 7, y: dot.y),
                        anchor: .leading
                    )
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Named targets. Not a window boresight. Hertzsprung is not plotted.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityLabel("Geographic targets from the flyby. Hertzsprung is not plotted.")
    }
}

private func framePrefetchToken(_ pair: FramePair, pixels: CGFloat, small: Bool) -> String {
    let bucket = MediaStore.pixelBucket(pixels)
    return "\(small)|\(pair.current?.file ?? "")|\(pair.next?.file ?? "")@\(bucket)"
}

enum Stamp {
    static func clock(_ utc: String) -> String {
        guard let separator = utc.firstIndex(of: "T") else { return utc }
        let time = utc[utc.index(after: separator)...]
        return String(time.prefix(8))
    }
}

extension PlaybackModel {
    func pair(for side: WindowSide) -> FramePair {
        FrameSelection.visiblePair(at: utc, window: side, frames: timeline?.frames ?? [])
    }

    func photo(_ frame: Frame, maxPixel: CGFloat) -> UIImage? {
        _ = frameCacheEpoch
        let cap = maxPixel > 1 ? maxPixel : 720
        return MediaStore.cachedImage(file: frame.file, small: phoneImages, maxPixel: cap)
    }

    func prefetch(_ frame: Frame, maxPixel: CGFloat) {
        let cap = maxPixel > 1 ? maxPixel : 720
        MediaStore.prefetch(file: frame.file, small: phoneImages, maxPixel: cap) { [weak self] in
            self?.noteFramesDecoded()
        }
    }

    func subtitleLine() -> TranscriptLine? {
        FrameSelection.subtitle(at: utc, track: trackID, lines: timeline?.lines ?? [])
    }
}
