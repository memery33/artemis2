import SwiftUI
import UIKit

/// Aristarchus Plateau and Reiner Gamma. The quote UTC is a real transcript line.
enum CraterKind: String, Identifiable, Equatable {
    case aristarchus
    case reiner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aristarchus: return "Aristarchus"
        case .reiner: return "Reiner Gamma"
        }
    }

    var targetID: String {
        switch self {
        case .aristarchus: return "Aristarchus Plateau"
        case .reiner: return "Reiner Gamma"
        }
    }

    var siteID: String {
        switch self {
        case .aristarchus: return "aristarchus"
        case .reiner: return "reiner-gamma"
        }
    }

    /// Wiseman on the albedo, then Wiseman on the weekly-update background.
    var quoteUTC: String {
        switch self {
        case .aristarchus: return "2026-04-06T19:38:52.750Z"
        case .reiner: return "2026-04-06T19:42:18.035Z"
        }
    }

    /// Feature numbers are the USGS gazetteer ids already stored on the sites.
    var kicker: String {
        switch self {
        case .aristarchus: return "Crater · feature 380"
        case .reiner: return "Albedo feature · 4987"
        }
    }

    init?(targetID: String) {
        switch targetID {
        case "Aristarchus Plateau": self = .aristarchus
        case "Reiner Gamma": self = .reiner
        default: return nil
        }
    }
}

struct HybridStage: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var flight
    @State private var panelOpen = false
    /// Finger travel while the sheet is tracking. Zero once it snaps.
    @State private var dragTranslation: CGFloat = 0
    @State private var crater: CraterKind?

    var body: some View {
        GeometryReader { geo in
            let panelHeight = min(460, max(340, geo.size.height * 0.5))
            ZStack {
                HybridColor.ground.ignoresSafeArea()
                if crater == nil {
                    flightPhoto
                        .matchedGeometryEffect(id: "flyby-photo", in: flight)
                }
                vignette
                chrome(panelHeight: panelHeight, size: geo.size)
                    .modifier(ApproachChrome())
                if let crater {
                    CraterPage(kind: crater, frame: craterFrame(crater), namespace: flight) {
                        self.crater = nil
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: crater)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task(id: shownFrame?.file) {
            guard let frame = shownFrame else { return }
            model.prefetch(frame, maxPixel: 1400)
        }
        .task(id: crater?.id) {
            guard let crater, let frame = craterFrame(crater) else { return }
            model.prefetch(frame, maxPixel: 1400)
        }
    }

    private func craterFrame(_ kind: CraterKind) -> Frame? {
        HybridFrames.craterHero(kind, frames: model.timeline?.frames ?? [])
    }

    private var shownFrame: Frame? {
        HybridFrames.shown(at: model.utc, side: model.window, timeline: model.timeline, span: model.activeSpan)
    }

    @ViewBuilder
    private var flightPhoto: some View {
        if let frame = shownFrame, let image = model.photo(frame, maxPixel: 1400) {
            let place = HybridFrames.placement(frame)
            let photo = placed(image, place)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
                .accessibilityAddTraits(.isImage)
            ZStack {
                placed(image, place)
                    .blur(radius: 28)
                    .opacity(0.32)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                if let kind = CraterKind(targetID: frame.targetID) {
                    Button {
                        crater = kind
                    } label: {
                        photo
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("open-crater")
                    .accessibilityLabel("Open \(kind.title)")
                    .accessibilityHint(FrameSelection.photoAccessLabel(frame))
                } else {
                    photo
                }
            }
            .ignoresSafeArea()
        }
    }

    private var vignette: some View {
        ZStack {
            RadialGradient(
                colors: [.clear, .black.opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 80,
                endRadius: 560
            )
            LinearGradient(
                colors: [Color.white.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.16)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func placed(_ image: UIImage, _ place: HybridFrames.Placement) -> PlacedPhoto {
        PlacedPhoto(
            image: image,
            objectX: place.x,
            objectY: place.y,
            zoom: place.zoom,
            focus: place.focus
        )
    }

    private func chrome(panelHeight: CGFloat, size: CGSize) -> some View {
        let shift = sheetShift(height: panelHeight)
        let revealed = panelHeight - shift
        return ZStack {
            if crater == nil, revealed < 80, shownFrame != nil {
                VStack {
                    Spacer()
                    HStack {
                        DocumentaryCaption(compact: false, includeCredit: true)
                            .frame(maxWidth: 280, alignment: .leading)
                        Spacer(minLength: 20)
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 108)
                }
            }
            if crater == nil, revealed >= 80, shownFrame != nil {
                VStack {
                    Spacer()
                    HStack {
                        CreditLine()
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, revealed + 10)
                }
            }
            if crater == nil {
                sheet(panelHeight: panelHeight)
                    .offset(y: shift)
                if revealed < 72 {
                    collapsedCue(panelHeight: panelHeight)
                }
                bottomEdge(panelHeight: panelHeight)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func sheet(panelHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 0) {
                ControlPanel(
                    height: panelHeight,
                    onClose: { setPanelOpen(false, height: panelHeight) },
                    onDragChanged: trackPanelDrag,
                    onDragEnded: { translation, predicted in
                        finishPanelDrag(translation: translation, predicted: predicted, height: panelHeight)
                    }
                )
                FlybyRuler { kind in
                    crater = kind
                }
                .frame(width: 150)
            }
            .frame(height: panelHeight)
            .background { panelFill }
        }
    }

    private var panelFill: some View {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.34))
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.32))
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
    }

    private func collapsedCue(panelHeight: CGFloat) -> some View {
        VStack {
            Spacer()
            Button {
                setPanelOpen(true, height: panelHeight)
            } label: {
                VStack(spacing: 8) {
                    Capsule()
                        .fill(HybridColor.cream.opacity(0.72))
                        .frame(width: 36, height: 4)
                    cueProgress
                        .frame(width: 148, height: 8)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Controls")
            .accessibilityIdentifier("open-panel")
            .accessibilityHint("Opens playback, the timeline, windows, and crew audio")
            .simultaneousGesture(panelDrag(panelHeight: panelHeight))
            .padding(.bottom, 44)
        }
    }

    /// The bottom edge of the screen. A drag here tracks the sheet; a tap stays on the handle.
    private func bottomEdge(panelHeight: CGFloat) -> some View {
        VStack {
            Spacer()
            Color.clear
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(panelDrag(panelHeight: panelHeight))
                .accessibilityElement()
                .accessibilityIdentifier("panel-edge")
                .accessibilityLabel("Swipe up for controls")
        }
    }

    private func sheetShift(height: CGFloat) -> CGFloat {
        let resting: CGFloat = panelOpen ? 0 : height
        return min(height, max(0, resting + dragTranslation))
    }

    private func setPanelOpen(_ open: Bool, height: CGFloat) {
        let visual = sheetShift(height: height)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            panelOpen = open
            dragTranslation = visual - (open ? 0 : height)
        }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.38)) {
            dragTranslation = 0
        }
    }

    private func trackPanelDrag(_ translation: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragTranslation = translation
        }
    }

    private func finishPanelDrag(translation: CGFloat, predicted: CGFloat, height: CGFloat) {
        let shouldOpen: Bool
        if panelOpen {
            shouldOpen = max(translation, predicted) < 72
        } else {
            shouldOpen = min(translation, predicted) < -48
        }
        setPanelOpen(shouldOpen, height: height)
    }

    private func panelDrag(panelHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                trackPanelDrag(value.translation.height)
            }
            .onEnded { value in
                finishPanelDrag(
                    translation: value.translation.height,
                    predicted: value.predictedEndTranslation.height,
                    height: panelHeight
                )
            }
    }

    private var cueProgress: some View {
        GeometryReader { geo in
            let fraction = HybridClock.fraction(date: model.utc, timeline: model.timeline)
            ZStack(alignment: .leading) {
                Capsule().fill(HybridColor.cream.opacity(0.28))
                Capsule()
                    .fill(HybridColor.gold)
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .accessibilityHidden(true)
    }
}

enum HybridFrames {
    struct Placement {
        var x: CGFloat
        var y: CGFloat
        var zoom: CGFloat
        /// True when `x` and `y` are a point in the image to center. False keeps CSS object-position.
        var focus: Bool
    }

    static func shown(at time: Date, side: WindowSide, timeline: Timeline?, span: TimeSpan?) -> Frame? {
        let frames = timeline?.frames ?? []
        if side == .nikon {
            return windowTwo(at: time, frames: frames)
        }
        let pair: FramePair
        if let span {
            pair = FrameSelection.visiblePair(
                at: time,
                window: side,
                frames: frames,
                spanStart: span.start,
                spanEnd: span.end
            )
        } else {
            pair = FrameSelection.visiblePair(at: time, window: side, frames: frames)
        }
        if let current = pair.current { return current }
        if let next = pair.next { return next }
        let rows = FrameSelection.frames(frames, window: side)
        return rows.min { lhs, rhs in
            let left = abs(lhs.date.timeIntervalSince(time))
            let right = abs(rhs.date.timeIntervalSince(time))
            if left != right { return left < right }
            return lhs.date < rhs.date
        }
    }

    /// Window 2 (D5) only. The Z9 frames are the cabin: a bright slit at the top and hardware below.
    /// Until the first frame tagged Moon, that frame stays up, at its own capture time.
    static func windowTwo(at time: Date, frames: [Frame]) -> Frame? {
        let rows = frames.filter { $0.instrument == "nkd5015" }.sorted { $0.date < $1.date }
        guard !rows.isEmpty else { return nil }
        if let moon = rows.first(where: { $0.targetID == "Moon" }), time < moon.date {
            return moon
        }
        if let taken = rows.last(where: { $0.date <= time }) {
            return taken
        }
        return rows[0]
    }

    /// A Window 2 frame of this crater, not whatever the playback clock is showing.
    /// Reiner Gamma uses art002e009943 (19:42:32.550 UTC). Its control hull reaches 300.94° E,
    /// beside the albedo center at 301.04° E, and the picture is the lunar surface.
    /// Aristarchus uses art002e009806 (19:35:52.140 UTC), the first frame tagged Aristarchus Plateau.
    static func craterHero(_ kind: CraterKind, frames: [Frame]) -> Frame? {
        let nasaID: String
        switch kind {
        case .aristarchus: nasaID = "art002e009806"
        case .reiner: nasaID = "art002e009943"
        }
        if let frame = frames.first(where: { $0.nasaID == nasaID }) {
            return frame
        }
        return frames.first { $0.targetID == kind.targetID && $0.instrument == "nkd5015" }
    }

    /// Cab frames keep the Moon on the right. A Moon disk is centered and zoomed to the edges.
    /// Other Window 2 frames keep the lit surface, which sits left of the sky.
    static func placement(_ frame: Frame) -> Placement {
        if frame.instrument == "cab2" {
            return Placement(x: 0.34, y: 0.42, zoom: 1, focus: false)
        }
        if frame.targetID == "Moon" {
            return Placement(x: 0.36, y: 0.59, zoom: 1.38, focus: true)
        }
        return Placement(x: 0.30, y: 0.50, zoom: 1.08, focus: true)
    }
}

enum HybridClock {
    static func domain(timeline: Timeline?) -> (start: Date, end: Date)? {
        guard let timeline else { return nil }
        let end = FlybyEphemeris.bundled.flatMap {
            FlybyPath.closestApproach($0.samples, radiusKm: $0.document.radiusKm)?.date
        } ?? timeline.window.end
        return (timeline.window.start, end)
    }

    static func fraction(date: Date, timeline: Timeline?) -> Double {
        guard let domain = domain(timeline: timeline) else { return 0 }
        let span = domain.end.timeIntervalSince(domain.start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(domain.start) / span))
    }
}

struct PlacedPhoto: View {
    var image: UIImage
    var objectX: CGFloat
    var objectY: CGFloat
    var zoom: CGFloat = 1
    var focus: Bool = false

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedSize(image: image.size, in: geo.size)
            let origin = origin(fitted: fitted, in: geo.size)
            Image(uiImage: image)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .position(x: origin.x + fitted.width / 2, y: origin.y + fitted.height / 2)
        }
    }

    private func fittedSize(image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = max(box.width / image.width, box.height / image.height) * max(zoom, 1)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    private func origin(fitted: CGSize, in box: CGSize) -> CGPoint {
        if focus {
            var centerX = box.width / 2 + (0.5 - objectX) * fitted.width
            var centerY = box.height / 2 + (0.5 - objectY) * fitted.height
            centerX = min(max(centerX, box.width - fitted.width / 2), fitted.width / 2)
            centerY = min(max(centerY, box.height - fitted.height / 2), fitted.height / 2)
            return CGPoint(x: centerX - fitted.width / 2, y: centerY - fitted.height / 2)
        }
        return CGPoint(
            x: (box.width - fitted.width) * objectX,
            y: (box.height - fitted.height) * objectY
        )
    }
}

struct DocumentaryCaption: View {
    @EnvironmentObject private var model: PlaybackModel
    var compact: Bool
    var includeCredit: Bool

    private var line: TranscriptLine? {
        LyricFocus.focus(at: model.utc, track: model.trackID, lines: model.timeline?.lines ?? []).current
    }

    private var frame: Frame? {
        HybridFrames.shown(at: model.utc, side: model.window, timeline: model.timeline, span: model.activeSpan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if let line {
                Text(line.speaker.uppercased())
                    .font(HybridFont.text(11, relativeTo: .caption2))
                    .tracking(1.6)
                    .foregroundStyle(HybridColor.gold)
                Text(line.text)
                    .font(HybridFont.display(compact ? 15 : 28, relativeTo: compact ? .subheadline : .title2, italic: true))
                    .foregroundStyle(HybridColor.cream)
                    .lineLimit(compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let frame {
                Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC")
                    .font(HybridFont.text(12, relativeTo: .caption))
                    .foregroundStyle(HybridColor.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if includeCredit {
                CreditLine()
            }
        }
        .shadow(color: .black.opacity(0.65), radius: compact ? 0 : 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("window-caption")
    }
}

struct ControlPanel: View {
    @EnvironmentObject private var model: PlaybackModel
    var height: CGFloat
    var onClose: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: (_ translation: CGFloat, _ predicted: CGFloat) -> Void
    @State private var about = false
    @State private var transcript = false
    @State private var moments = false
    @State private var suppressCloseTap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            handle
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    clocks
                    transport
                    DocumentaryCaption(compact: true, includeCredit: false)
                    windowRow
                    CrewRow()
                    secondaryRow
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.bottom, 36)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $about) { AboutView() }
        .sheet(isPresented: $transcript) { TranscriptSheet() }
        .sheet(isPresented: $moments) { MomentsSheet() }
    }

    private var handle: some View {
        Capsule()
            .fill(HybridColor.cream.opacity(0.72))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                if suppressCloseTap {
                    suppressCloseTap = false
                    return
                }
                onClose()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .onChanged { value in
                        suppressCloseTap = true
                        onDragChanged(value.translation.height)
                    }
                    .onEnded { value in
                        onDragEnded(value.translation.height, value.predictedEndTranslation.height)
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            suppressCloseTap = false
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Close controls")
            .accessibilityIdentifier("close-panel")
            .accessibilityHint("Drag down to close")
    }

    private var clocks: some View {
        let clocks = ClockMath.format(date: model.utc, epoch: model.timeline?.epoch ?? model.utc)
        let time = clocks.utc.replacingOccurrences(of: " UTC", with: "")
        return VStack(alignment: .leading, spacing: 2) {
            Text(time)
                .font(HybridFont.display(32, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(HybridColor.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityHidden(true)
            Text("\(clocks.utc) · \(clocks.met)")
                .font(HybridFont.text(13, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(HybridColor.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("mission-clock")
        }
    }

    private var transport: some View {
        HStack(spacing: 22) {
            skip(label: "−15s", access: "Skip back 15 seconds", identifier: "skip-back", seconds: -PlaybackModel.skipInterval)
            play
            skip(label: "+15s", access: "Skip forward 15 seconds", identifier: "skip-forward", seconds: PlaybackModel.skipInterval)
        }
    }

    private var play: some View {
        let playing = model.playing
        return Button(action: { model.toggle() }) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(HybridColor.cream)
                .frame(width: 56, height: 56)
                .background {
                    ZStack {
                        Circle().fill(HybridColor.cream.opacity(0.08))
                        Circle().strokeBorder(HybridColor.gold.opacity(0.9), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playback-toggle")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    private func skip(label: String, access: String, identifier: String, seconds: TimeInterval) -> some View {
        Button {
            model.skip(by: seconds)
        } label: {
            Text(label)
                .font(HybridFont.text(15, relativeTo: .body))
                .fontWeight(.semibold)
                .foregroundStyle(HybridColor.cream)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(access)
        .accessibilityIdentifier(identifier)
    }

    private var windowRow: some View {
        HStack(spacing: 8) {
            windowButton("Window 2", side: .nikon, identifier: "window-nikon")
            windowButton("Window 3", side: .cab, identifier: "window-cab")
        }
    }

    private func windowButton(_ title: String, side: WindowSide, identifier: String) -> some View {
        let selected = model.window == side
        return Button {
            model.setWindow(side)
        } label: {
            Text(title)
                .font(HybridFont.text(13, relativeTo: .footnote))
                .fontWeight(.medium)
                .foregroundStyle(selected ? HybridColor.ink : HybridColor.dim)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background {
                    Capsule().fill(selected ? HybridColor.cream.opacity(0.92) : Color.white.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }

    private var secondaryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                textButton(model.range == .flyby ? "Cab run" : "Flyby", identifier: "span-toggle") {
                    if model.range == .flyby {
                        model.showCabRun()
                    } else {
                        model.showFlyby()
                    }
                }
                textButton(model.spatial ? "Spatial on" : "Spatial", identifier: "spatial-toggle") {
                    model.setSpatial(!model.spatial)
                }
            }
            HStack(spacing: 8) {
                textButton("Lines", identifier: "lines-button") { transcript = true }
                textButton("Moments", identifier: "moments-button") { moments = true }
                textButton("About", identifier: "about-button") { about = true }
            }
        }
    }

    private func textButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(HybridFont.text(15, relativeTo: .subheadline))
                .fontWeight(.semibold)
                .foregroundStyle(HybridColor.cream)
                .frame(minHeight: 44)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }
}

struct FlybyRuler: View {
    @EnvironmentObject private var model: PlaybackModel
    var onCrater: (CraterKind) -> Void

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.45)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                tickLayer(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
                labelColumn
                    .padding(.bottom, 44)
                    .padding(.trailing, 34)
            }
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(width: 28)
                    .contentShape(Rectangle())
                    .gesture(scrub(height: height))
                    .accessibilityElement()
                    .accessibilityLabel("Flyby timeline")
                    .accessibilityValue(ClockMath.utcText(model.utc))
                    .accessibilityAdjustableAction { direction in
                        model.accessibilityAdjust(direction)
                    }
            }
        }
    }

    private var milestones: [Milestone] {
        guard let timeline = model.timeline else { return [] }
        return MilestoneList.derive(timeline)
    }

    private func tickLayer(height: CGFloat) -> some View {
        let timeline = model.timeline
        return ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(HybridColor.cream.opacity(0.32))
                .frame(width: 1, height: max(0, height - 96))
                .padding(.top, 54)
                .padding(.trailing, 18)
            if let window = timeline?.window {
                spanBar(from: window.start, to: window.end, height: height, width: 2, trailing: 30, color: HybridColor.gold)
            }
            if let cab = timeline?.cabRun {
                spanBar(from: cab.start, to: cab.end, height: height, width: 2, trailing: 24, color: HybridColor.cream.opacity(0.9))
            }
            ForEach(milestones) { milestone in
                Capsule()
                    .fill(milestone.track == nil && milestone.id.hasPrefix("photo:") ? HybridColor.gold : HybridColor.cream.opacity(0.55))
                    .frame(width: milestone.id.hasPrefix("photo:") ? 12 : 6, height: 1)
                    .padding(.trailing, 14)
                    .offset(y: y(milestone.date, height: height))
            }
            Capsule()
                .fill(HybridColor.cream)
                .frame(width: 22, height: 2)
                .padding(.trailing, 10)
                .offset(y: y(model.utc, height: height))
                .shadow(color: HybridColor.gold.opacity(0.9), radius: 4)
        }
        .allowsHitTesting(false)
    }

    private func spanBar(from start: Date, to end: Date, height: CGFloat, width: CGFloat, trailing: CGFloat, color: Color) -> some View {
        let top = y(start, height: height)
        let bottom = y(end, height: height)
        return Capsule()
            .fill(color)
            .frame(width: width, height: max(2, bottom - top))
            .padding(.trailing, trailing)
            .offset(y: top)
    }

    private var labelColumn: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if let line = quote(utc: "2026-04-06T19:33:02.700Z") {
                labelButton(time: Stamp.clock(line.utc), name: "Aristarchus", now: isNow(line.date), identifier: "milestone-aristarchus") {
                    onCrater(.aristarchus)
                }
            }
            if let line = quote(utc: "2026-04-06T19:36:05.938Z") {
                labelButton(time: Stamp.clock(line.utc), name: "Wiseman's line", now: isNow(line.date), identifier: "milestone-wiseman") {
                    model.seek(to: line.date, markEnd: false)
                }
            }
            if let line = quote(utc: "2026-04-06T19:40:57.609Z") {
                labelButton(time: Stamp.clock(line.utc), name: "Reiner Gamma", now: isNow(line.date), identifier: "milestone-reiner") {
                    onCrater(.reiner)
                }
            }
            if let approach = approachDate {
                labelButton(
                    time: ClockMath.utcText(approach).replacingOccurrences(of: " UTC", with: ""),
                    name: "Closest approach",
                    now: isNow(approach),
                    identifier: "milestone-approach"
                ) {
                    parkBeforeEnd(approach)
                }
            }
        }
        .frame(width: 108, alignment: .trailing)
    }

    private func labelButton(
        time: String,
        name: String,
        now: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(time)
                    .font(HybridFont.text(11, relativeTo: .caption2).monospacedDigit())
                    .fontWeight(.semibold)
                Text(name)
                    .font(HybridFont.text(11, relativeTo: .caption2))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(now ? HybridColor.gold : HybridColor.cream)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(name)
    }

    private func quote(utc: String) -> TranscriptLine? {
        model.timeline?.lines.first { $0.utc == utc }
    }

    private func isNow(_ date: Date) -> Bool {
        abs(model.utc.timeIntervalSince(date)) < 1.5
    }

    private var approachDate: Date? {
        guard let bundled = FlybyEphemeris.bundled else { return nil }
        return FlybyPath.closestApproach(bundled.samples, radiusKm: bundled.document.radiusKm)?.date
    }

    private func y(_ date: Date, height: CGFloat) -> CGFloat {
        HybridClock.fraction(date: date, timeline: model.timeline) * height
    }

    private func scrub(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let date = date(atY: value.location.y, height: height) else { return }
                if !model.scrubbing { model.beginScrub() }
                land(on: date)
            }
            .onEnded { _ in
                model.endScrub(markEnd: false)
            }
    }

    private func date(atY y: CGFloat, height: CGFloat) -> Date? {
        guard height > 1, let domain = HybridClock.domain(timeline: model.timeline) else { return nil }
        let span = domain.end.timeIntervalSince(domain.start)
        guard span > 0 else { return nil }
        return domain.start.addingTimeInterval(span * min(1, max(0, y / height)))
    }

    /// The ruler runs through closest approach. A drag past the observation window
    /// parks inside the real span and does not end the Live Activity.
    private func land(on date: Date) {
        guard let timeline = model.timeline else { return }
        if let cab = timeline.cabRun, date >= cab.start {
            if model.trackID != "pcd2" {
                model.trackID = "pcd2"
                if let member = timeline.crew.first(where: { $0.track == "pcd2" }) {
                    model.crewID = member.id
                }
            }
            if model.range != .cab { model.range = .cab }
            if model.window != .cab { model.setWindow(.cab) }
            if date < cab.end {
                model.utc = date
            } else {
                model.utc = cab.end.addingTimeInterval(-0.05)
            }
            return
        }
        let leavingCab = model.range == .cab
        if model.range != .flyby { model.range = .flyby }
        if leavingCab, model.window != .nikon { model.setWindow(.nikon) }
        if date >= timeline.window.start, date < timeline.window.end {
            model.utc = date
        } else {
            model.utc = timeline.window.end.addingTimeInterval(-0.05)
        }
    }

    private func parkBeforeEnd(_ date: Date) {
        guard let span = model.activeSpan else { return }
        let parked = min(date, span.end.addingTimeInterval(-0.05))
        model.seek(to: max(parked, span.start), markEnd: false)
    }
}

struct CraterPage: View {
    @EnvironmentObject private var model: PlaybackModel
    var kind: CraterKind
    var frame: Frame?
    var namespace: Namespace.ID
    var onClose: () -> Void

    private var card: ExhibitCard? {
        ExhibitLibrary.cards.first { $0.targetID == kind.targetID }
    }

    private var site: LunarSite? {
        LunarSites.marked.first { $0.id == kind.siteID }
    }

    private var quote: TranscriptLine? {
        model.timeline?.lines.first { $0.utc == kind.quoteUTC }
    }

    private var aim: MapTarget? {
        model.timeline?.targets.first { $0.name == kind.targetID && $0.geographic }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HybridColor.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TrackMapView(date: model.utc, emphasized: kind.siteID)
                            .frame(height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text(kind.kicker.uppercased())
                            .font(HybridFont.text(11, relativeTo: .caption2))
                            .tracking(1.6)
                            .foregroundStyle(HybridColor.gold)
                        Text(kind.title)
                            .font(HybridFont.display(40, relativeTo: .largeTitle))
                            .foregroundStyle(HybridColor.cream)
                        if let site {
                            Text("\(hemisphere(site.latitude, positive: "N", negative: "S")), \(hemisphere(site.longitudeEast, positive: "E", negative: "W"))")
                                .font(HybridFont.text(13, relativeTo: .footnote))
                                .foregroundStyle(HybridColor.dim)
                        }
                        if let card {
                            Text(card.body)
                                .font(HybridFont.display(22, relativeTo: .title3))
                                .foregroundStyle(HybridColor.cream)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("crater-why")
                        }
                        if let quote {
                            Text(quote.text)
                                .font(HybridFont.display(18, relativeTo: .body, italic: true))
                                .foregroundStyle(HybridColor.cream)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(quote.speaker) · \(Stamp.clock(quote.utc)) UTC")
                                .font(HybridFont.text(12, relativeTo: .caption))
                                .foregroundStyle(HybridColor.dim)
                        }
                        disclosure
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
            }
            Button(action: onClose) {
                Text("Close")
                    .font(HybridFont.text(15, relativeTo: .body))
                    .fontWeight(.semibold)
                    .foregroundStyle(HybridColor.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(HybridColor.cream, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 54)
            .accessibilityIdentifier("close-crater")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("crater-page")
    }

    @ViewBuilder
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            HybridColor.ground
            if let frame, let image = model.photo(frame, maxPixel: 1400) {
                let place = HybridFrames.placement(frame)
                PlacedPhoto(
                    image: image,
                    objectX: place.x,
                    objectY: place.y,
                    zoom: place.zoom,
                    focus: place.focus
                )
                .frame(height: 280)
                .clipped()
                .matchedGeometryEffect(id: "flyby-photo", in: namespace)
                .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
            }
            LinearGradient(colors: [.clear, HybridColor.ground], startPoint: .center, endPoint: .bottom)
                .frame(height: 90)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 4) {
                if let frame {
                    Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC")
                        .font(HybridFont.text(12, relativeTo: .caption))
                        .foregroundStyle(HybridColor.cream)
                }
                CreditLine()
            }
            .padding(16)
        }
        .frame(height: 280)
        .clipped()
    }

    private var disclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                if let site {
                    Text(site.source)
                }
                if let aim {
                    Text("Lunar Targeting Plan aim \(hemisphere(aim.lat, positive: "N", negative: "S")), \(hemisphere(aim.lon, positive: "E", negative: "W")). Not the USGS center.")
                }
                if let card {
                    Text(card.source)
                }
                if let note = model.timeline?.pointing.note {
                    Text(note)
                }
            }
            .font(HybridFont.text(13, relativeTo: .footnote))
            .foregroundStyle(HybridColor.dim)
            .padding(.top, 8)
        } label: {
            Text("About this data")
                .font(HybridFont.text(15, relativeTo: .subheadline))
                .fontWeight(.semibold)
                .foregroundStyle(HybridColor.cream)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .tint(HybridColor.gold)
        .accessibilityIdentifier("about-this-data")
    }

    private func hemisphere(_ value: Double, positive: String, negative: String) -> String {
        String(format: "%.2f° %@", abs(value), value >= 0 ? positive : negative)
    }
}
