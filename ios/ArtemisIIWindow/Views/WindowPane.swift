import SwiftUI

struct WindowPane: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var turn: Double = 0
    /// Landscape draws the clocks, quote, and credit on the glass.
    var glassChrome: Bool = false

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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
                    .accessibilityAddTraits(.isImage)
                }
                if mix > 0, let frame = pair.next, let image = model.photo(frame, maxPixel: pixels) {
                    placed(
                        image,
                        motion: motion(progress: 0, index: pair.index + 1),
                        size: geo.size
                    )
                    .opacity(mix)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
                    .accessibilityAddTraits(.isImage)
                }
                if pair.current == nil && mix == 0 {
                    Text(emptyCopy(pair))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(24)
                }
                if pair.outsideSpan, let frame = pair.current {
                    VStack {
                        Text(FrameSelection.outsideSpanNotice(frame: frame, now: model.utc))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.82))
                            .accessibilityLabel(
                                FrameSelection.outsideSpanNotice(frame: frame, now: model.utc, includeAge: false)
                            )
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }
                if glassChrome {
                    landscapeChrome
                } else {
                    subtitle
                }
                if side == .nikon {
                    bezel
                }
            }
            .task(id: framePrefetchToken(pair, pixels: pixels, small: model.phoneImages, epoch: model.frameCacheEpoch)) {
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

    private var lyricFocus: LyricFocus {
        LyricFocus.focus(at: model.utc, track: model.trackID, lines: model.timeline?.lines ?? [])
    }

    private var subtitle: some View {
        VStack {
            Spacer()
            LyricLines(focus: lyricFocus)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.55))
                .padding(.horizontal, side == .nikon ? 18 : 6)
                .padding(.bottom, side == .nikon ? 20 : 6)
        }
        .allowsHitTesting(false)
    }

    /// Clocks, the whole quote, and the credit sit on the pane. Padding keeps
    /// them inside the bezel and clear of the rounded corners.
    private var landscapeChrome: some View {
        VStack(spacing: 0) {
            ClockReadout()
                .padding(.horizontal, 22)
                .padding(.top, side == .nikon ? 26 : 10)
                .shadow(color: .black.opacity(0.85), radius: 3, y: 1)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                LyricLines(focus: lyricFocus)
                FrameCaption(side: side)
                CreditLine()
                StatusLines()
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.55))
            .padding(.horizontal, side == .nikon ? 18 : 6)
            .padding(.bottom, side == .nikon ? 22 : 8)
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
                if side == .cab, pair.outsideSpan {
                    Text(FrameSelection.outsideSpanNotice(frame: frame, now: model.utc))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(
                            FrameSelection.outsideSpanNotice(frame: frame, now: model.utc, includeAge: false)
                        )
                } else if side == .cab {
                    let note = cabNote(frame)
                    Text(note.visible)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityLabel(note.spoken)
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

    private func cabNote(_ frame: Frame) -> (visible: String, spoken: String) {
        var spoken = ["Taken \(Stamp.clock(frame.utc)) UTC · \(frame.nasaID)."]
        spoken.append(FrameSelection.appearance(frame))
        var visible = spoken
        if let age = FrameSelection.clockOffset(now: model.utc, taken: frame.date) {
            visible.append(age)
        }
        return (visible.joined(separator: " "), spoken.joined(separator: " "))
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
                            .task(id: framePrefetchToken(pair, pixels: pixels, small: model.phoneImages, epoch: model.frameCacheEpoch)) {
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
                    .font(pair.outsideSpan ? .headline : .caption2)
                    .foregroundStyle(.white.opacity(pair.outsideSpan ? 1 : 0.8))
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
        if pair.outsideSpan {
            return FrameSelection.outsideSpanNotice(frame: frame, now: model.utc)
        }
        let when = Stamp.clock(frame.utc)
        if let gap = FrameSelection.clockGap(now: model.utc, taken: frame.date) {
            return "\(label). Taken \(when) UTC, \(gap)."
        }
        return "\(label). Taken \(when) UTC."
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
                            .task(id: "\(model.frameCacheEpoch)|\(model.phoneImages)|\(card.file)@\(MediaStore.pixelBucket(pixels))") {
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
        .accessibilityIdentifier("mission-clock")
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
                let plateWidth = Double(size.width)
                let plateHeight = max(1, Double(size.height) - 8)
                let inset = 3.0
                let bounds = MapProjection.LabelBounds(
                    x: inset,
                    y: inset,
                    width: max(0, plateWidth - inset * 2),
                    height: max(0, Double(size.height) - inset * 2)
                )
                var anchors: [MapProjection.LabelAnchor] = []
                var lines: [String: GraphicsContext.ResolvedText] = [:]
                var measured: [String: CGSize] = [:]
                for target in targets {
                    guard let raw = MapProjection.point(
                        lon: target.lon,
                        lat: target.lat,
                        width: plateWidth,
                        height: plateHeight
                    ) else { continue }
                    let text = Text(target.name).font(.system(size: 9)).foregroundStyle(.white)
                    let line = context.resolve(text)
                    let textSize = line.measure(in: CGSize(width: 480, height: 40))
                    anchors.append(
                        MapProjection.LabelAnchor(
                            name: target.name,
                            x: raw.x,
                            y: raw.y,
                            width: Double(textSize.width),
                            height: Double(textSize.height)
                        )
                    )
                    lines[target.name] = line
                    measured[target.name] = textSize
                }
                let boxes = MapProjection.fitLabels(anchors, in: bounds)
                for box in boxes {
                    let dot = CGPoint(
                        x: min(max(4.0, box.dotX), plateWidth - 4),
                        y: min(max(4.0, box.dotY), Double(size.height) - 4)
                    )
                    let mark = CGRect(x: dot.x - 2.5, y: dot.y - 2.5, width: 5, height: 5)
                    context.fill(Path(ellipseIn: mark), with: .color(.white))
                    guard let line = lines[box.name] else { continue }
                    let rect = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
                    if let natural = measured[box.name],
                       abs(natural.width - rect.width) < 0.75,
                       abs(natural.height - rect.height) < 0.75 {
                        context.draw(line, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
                    } else {
                        context.draw(line, in: rect)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Named targets. Not a window boresight. Hertzsprung is not plotted.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("geographic-targets")
        .accessibilityLabel("Geographic targets from the flyby. Hertzsprung is not plotted.")
    }
}

private func framePrefetchToken(_ pair: FramePair, pixels: CGFloat, small: Bool, epoch: Int) -> String {
    let bucket = MediaStore.pixelBucket(pixels)
    return "\(epoch)|\(small)|\(pair.current?.file ?? "")|\(pair.next?.file ?? "")@\(bucket)"
}

extension PlaybackModel {
    func pair(for side: WindowSide) -> FramePair {
        let frames = timeline?.frames ?? []
        guard let span = activeSpan else {
            return FrameSelection.visiblePair(at: utc, window: side, frames: frames)
        }
        return FrameSelection.visiblePair(
            at: utc,
            window: side,
            frames: frames,
            spanStart: span.start,
            spanEnd: span.end
        )
    }

    func photo(_ frame: Frame, maxPixel: CGFloat) -> UIImage? {
        _ = frameCacheEpoch
        let cap = maxPixel > 1 ? maxPixel : 720
        return MediaStore.cachedImage(file: frame.file, small: phoneImages, maxPixel: cap)
    }

    func prefetch(_ frame: Frame, maxPixel: CGFloat) {
        let cap = maxPixel > 1 ? maxPixel : 720
        MediaStore.prefetch(file: frame.file, small: phoneImages, maxPixel: cap) { [weak self] in
            self?.noteFramesDecoded(file: frame.file)
        }
    }

    func subtitleLine() -> TranscriptLine? {
        FrameSelection.subtitle(at: utc, track: trackID, lines: timeline?.lines ?? [])
    }
}
