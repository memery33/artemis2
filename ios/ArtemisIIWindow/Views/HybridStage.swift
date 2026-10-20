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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Namespace private var flight
    @State private var panelOpen = false
    /// Finger travel while the sheet is tracking. Zero once it snaps.
    @State private var dragTranslation: CGFloat = 0
    @State private var crater: CraterKind?
    /// Window bottom inset. The geometry reader below ignores the safe area, so its own inset is always 0.
    /// Seeded from the window before the first frame, then updated when the inset changes.
    @State private var safeBottom: CGFloat

    init() {
        _safeBottom = State(initialValue: Self.seededSafeBottom())
    }

    private static func seededSafeBottom() -> CGFloat {
        // SwiftUI runs View.body on the main actor. RootView.body builds StageView,
        // and StageView.body is the only caller of HybridStage(), so this init is
        // already on main. WindowSafeArea.bottom reads UIApplication and is
        // @MainActor; this init is not, so the read goes through assumeIsolated.
        // That check is the guarantee: the closure runs only when the caller is
        // on the main actor, and it traps if this init is ever reached off main.
        MainActor.assumeIsolated { WindowSafeArea.bottom }
    }

    var body: some View {
        GeometryReader { geo in
            let panelHeight = PanelMetrics.sheetHeight(screenHeight: geo.size.height, safeBottom: safeBottom)
            let pixels = ScreenImage.maxPixel(size: geo.size, scale: displayScale)
            ZStack {
                HybridColor.ground.ignoresSafeArea()
                if crater == nil {
                    flightPhoto(maxPixel: pixels)
                        .matchedGeometryEffect(id: "flyby-photo", in: flight)
                }
                vignette
                chrome(panelHeight: panelHeight, size: geo.size, safeBottom: safeBottom)
                    .modifier(ApproachChrome())
                if let crater {
                    CraterPage(
                        kind: crater,
                        frame: craterFrame(crater),
                        namespace: flight,
                        maxPixel: pixels
                    ) {
                        self.crater = nil
                    }
                }
                safeAreaEdge
                WindowSafeAreaReader { bottom in
                    if bottom != safeBottom {
                        safeBottom = bottom
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: crater)
            .defersSystemGestures(on: .bottom)
            .task(id: shownFrame?.file) {
                guard let frame = shownFrame else { return }
                model.prefetch(frame, maxPixel: pixels)
                if let upcoming = HybridFrames.upcomingWindowTwo(after: model.utc, frames: model.timeline?.frames ?? []) {
                    model.prefetch(upcoming, maxPixel: pixels)
                }
            }
            .task(id: crater?.id) {
                guard let crater, let frame = craterFrame(crater) else { return }
                model.prefetch(frame, maxPixel: pixels)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    /// One-point mark at the window's safe-area edge. The panel and the ruler use that same inset.
    private var safeAreaEdge: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .accessibilityElement()
                .accessibilityIdentifier("safe-area-bottom")
                .accessibilityLabel("Safe area bottom")
        }
        .padding(.bottom, safeBottom)
        .allowsHitTesting(false)
    }

    private func craterFrame(_ kind: CraterKind) -> Frame? {
        HybridFrames.craterHero(kind, frames: model.timeline?.frames ?? [])
    }

    private var shownFrame: Frame? {
        HybridFrames.shown(at: model.utc, side: model.window, timeline: model.timeline, span: model.activeSpan)
    }

    private func flightPhoto(maxPixel: CGFloat) -> some View {
        StableFramePhoto(frame: shownFrame, maxPixel: maxPixel) { image, frame in
            let place = HybridFrames.placement(frame)
            let photo = placed(image, place)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FrameSelection.photoAccessLabel(frame))
                .accessibilityAddTraits(.isImage)
            ZStack {
                placed(image, place)
                    .blur(radius: 28)
                    .opacity(0.32)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if let kind = CraterKind(targetID: frame.targetID) {
                    Button {
                        crater = kind
                    } label: {
                        photo.accessibilityHidden(true)
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

    private func chrome(panelHeight: CGFloat, size: CGSize, safeBottom: CGFloat) -> some View {
        let shift = sheetShift(height: panelHeight)
        let revealed = panelHeight - shift
        return ZStack {
            if crater == nil, revealed < 80, shownFrame != nil {
                closedCaption(size: size)
            }
            if crater == nil, revealed >= 80, shownFrame != nil {
                VStack {
                    Spacer()
                    if dynamicTypeSize.isAccessibilitySize {
                        CreditLine()
                            .frame(maxWidth: max(0, size.width - 40), alignment: .leading)
                            .padding(.leading, 20)
                            .padding(.bottom, revealed + 10)
                    } else {
                        HStack {
                            CreditLine()
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, revealed + 10)
                    }
                }
            }
            // While the panel is open the caption is off the stage, so the card can sit at the top.
            // The closed stage reserves that same card's height above the caption.
            if crater == nil, revealed >= 80, let gap = model.approachGap {
                VStack {
                    approachCard(gap, width: min(320, max(0, size.width - 40)))
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }
                .frame(width: size.width, height: size.height, alignment: .top)
            }
            if crater == nil {
                sheet(panelHeight: panelHeight, width: size.width, safeBottom: safeBottom)
                    .frame(width: size.width, alignment: .leading)
                    .offset(y: shift)
                // Stay mounted for the whole drag. Removing it mid-gesture
                // cancelled the swipe after the sheet had risen about 90 pt.
                if !panelOpen {
                    collapsedCue(panelHeight: panelHeight)
                }
                bottomEdge(panelHeight: panelHeight)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Closed caption. With the closest-approach card up, the card keeps its height and the
    /// caption is offered only the space under it, at every Dynamic Type size.
    @ViewBuilder
    private func closedCaption(size: CGSize) -> some View {
        let captionWidth: CGFloat = min(280, max(0, size.width - 40))
        let captionHeight: CGFloat = max(
            0,
            size.height - ClosedCaptionMetrics.bottomClearance - ClosedCaptionMetrics.topClearance
        )
        if let gap = model.approachGap {
            ApproachColumn(spacing: 12) {
                approachCard(gap, width: min(320, max(0, size.width - 40)))
                    .padding(.top, 12)
                DocumentaryCaption(compact: false, includeCredit: true, fitOfferedHeight: true)
                    .frame(maxWidth: captionWidth, maxHeight: .infinity, alignment: .bottomLeading)
                    .clipped()
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.bottom, ClosedCaptionMetrics.bottomClearance)
            .frame(width: size.width, height: size.height, alignment: .top)
        } else {
            // Default type: max width 280 and no line cap. The longest quote is 414 pt
            // and the Controls handle stays at the bottom of the screen.
            // Accessibility sizes use a hard width and a height cap so a long word or
            // a tall quote cannot stretch the stage past the phone.
            VStack {
                Spacer()
                HStack {
                    if dynamicTypeSize.isAccessibilitySize {
                        DocumentaryCaption(compact: false, includeCredit: true)
                            .frame(width: captionWidth, alignment: .leading)
                            .frame(maxHeight: captionHeight, alignment: .top)
                            .clipped()
                    } else {
                        DocumentaryCaption(compact: false, includeCredit: true)
                            .frame(maxWidth: 280, alignment: .leading)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.leading, 20)
                .padding(.bottom, ClosedCaptionMetrics.bottomClearance)
            }
        }
    }

    private func approachCard(_ gap: String, width: CGFloat) -> some View {
        Text(gap)
            .font(
                model.approachInformational
                    ? HybridFont.display(16, relativeTo: .subheadline, italic: true)
                    : HybridFont.text(15, relativeTo: .subheadline)
            )
            .foregroundStyle(HybridColor.cream)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: width, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.62))
                    }
            }
            .accessibilityIdentifier("approach-gap")
            .accessibilityLabel(gap)
    }

    private func sheet(panelHeight: CGFloat, width: CGFloat, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            sheetColumns(panelHeight: panelHeight, safeBottom: safeBottom)
            .frame(width: width, height: panelHeight, alignment: .leading)
            .clipped()
            .background { panelFill }
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("control-panel")
                    .accessibilityLabel("Controls")
                    .accessibilityValue(panelOpen ? "open" : "closed")
            }
        }
    }

    /// Default type keeps the moments rail on the right. Accessibility sizes give the
    /// controls the full width; the same moments sit in the scroll column instead.
    @ViewBuilder
    private func sheetColumns(panelHeight: CGFloat, safeBottom: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            controlPanel(panelHeight: panelHeight, safeBottom: safeBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            HStack(alignment: .bottom, spacing: 0) {
                controlPanel(panelHeight: panelHeight, safeBottom: safeBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                FlybyRuler(safeBottom: safeBottom) { kind in
                    crater = kind
                }
                .frame(width: 176)
            }
        }
    }

    private func controlPanel(panelHeight: CGFloat, safeBottom: CGFloat) -> ControlPanel {
        ControlPanel(
            height: panelHeight,
            safeBottom: safeBottom,
            onClose: { setPanelOpen(false) },
            onDragChanged: trackPanelDrag,
            onDragEnded: { translation, predicted, velocity in
                finishPanelDrag(
                    translation: translation,
                    predicted: predicted,
                    velocity: velocity,
                    height: panelHeight
                )
            },
            onCrater: { kind in
                crater = kind
            }
        )
    }

    private var panelFill: some View {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                // 0.34 left cream type sitting on the bright lunar frames. The darker tint
                // keeps the secondary clock readable without changing the type color.
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.58))
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
                setPanelOpen(true)
            } label: {
                VStack(spacing: ClosedCaptionMetrics.cueSpacing) {
                    Capsule()
                        .fill(HybridColor.cream.opacity(0.72))
                        .frame(width: 36, height: ClosedCaptionMetrics.handleHeight)
                    cueProgress
                        .frame(width: 148, height: ClosedCaptionMetrics.progressHeight)
                }
                .padding(.vertical, ClosedCaptionMetrics.cueVerticalPadding)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Controls")
            .accessibilityIdentifier("open-panel")
            .accessibilityHint("Opens playback, the timeline, windows, and crew audio")
            .simultaneousGesture(panelDrag(panelHeight: panelHeight))
            .padding(.bottom, ClosedCaptionMetrics.controlsBottomInset)
        }
    }

    /// Drag strip above the home indicator. The bottom 20 pt is left alone so the
    /// system swipe can still reach the app switcher.
    private func bottomEdge(panelHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Color.clear
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .allowsHitTesting(!panelOpen)
                .gesture(panelDrag(panelHeight: panelHeight))
                .accessibilityElement()
                .accessibilityHidden(panelOpen)
                .accessibilityIdentifier("panel-edge")
                .accessibilityLabel("Swipe up for controls")
            Color.clear
                .frame(height: 20)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func sheetShift(height: CGFloat) -> CGFloat {
        let resting: CGFloat = panelOpen ? 0 : height
        return min(height, max(0, resting + dragTranslation))
    }

    private func setPanelOpen(_ open: Bool) {
        withAnimation(sheetSpring) {
            panelOpen = open
            dragTranslation = 0
        }
    }

    private var sheetSpring: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84)
    }

    private func trackPanelDrag(_ translation: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragTranslation = translation
        }
    }

    /// A quarter of the sheet, or a fast flick, commits. Anything shorter springs shut.
    private func finishPanelDrag(translation: CGFloat, predicted: CGFloat, velocity: CGFloat, height: CGFloat) {
        let threshold = max(72, height * 0.25)
        let flick: CGFloat = 700
        let projected = abs(predicted) >= abs(translation) ? predicted : translation
        let shouldOpen: Bool
        if velocity < -flick {
            shouldOpen = true
        } else if velocity > flick {
            shouldOpen = false
        } else if panelOpen {
            shouldOpen = projected < threshold
        } else {
            shouldOpen = projected < -threshold
        }
        setPanelOpen(shouldOpen)
    }

    private func panelDrag(panelHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                trackPanelDrag(value.translation.height)
            }
            .onEnded { value in
                finishPanelDrag(
                    translation: value.translation.height,
                    predicted: value.predictedEndTranslation.height,
                    velocity: value.velocity.height,
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

    /// The next Window 2 frame after `time`, prefetched so the pane never waits on an empty decode.
    static func upcomingWindowTwo(after time: Date, frames: [Frame]) -> Frame? {
        frames
            .filter { $0.instrument == "nkd5015" && $0.date > time }
            .min { $0.date < $1.date }
    }

    /// Window 2 (D5) only. The latest real frame at or before the clock stays up.
    /// Before the first frame, that first frame is shown, so Glushko (art002e009611,
    /// 19:33:59) is on screen through 19:34:29 instead of the later Moon frame.
    static func windowTwo(at time: Date, frames: [Frame]) -> Frame? {
        let rows = frames.filter { $0.instrument == "nkd5015" }.sorted { $0.date < $1.date }
        guard !rows.isEmpty else { return nil }
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
    /// Window 2 uses the stored brightness centroid when the frame has one, so a limb
    /// is not cropped onto the dark sky. Otherwise the lit surface sits left of the sky.
    static func placement(_ frame: Frame) -> Placement {
        if frame.instrument == "cab2" {
            // Dark Cab Cam frames keep the Moon as a small disk. Crop toward that limb.
            if frame.look == "dark" {
                if let x = frame.focusX, let y = frame.focusY {
                    return Placement(x: CGFloat(x), y: CGFloat(y), zoom: 2.8, focus: true)
                }
                return Placement(x: 0.54, y: 0.54, zoom: 2.8, focus: true)
            }
            return Placement(x: 0.34, y: 0.42, zoom: 1, focus: false)
        }
        if let x = frame.focusX, let y = frame.focusY {
            let zoom: CGFloat = frame.targetID == "Moon" ? 1.38 : 1.08
            return Placement(x: CGFloat(x), y: CGFloat(y), zoom: zoom, focus: true)
        }
        if frame.targetID == "Moon" {
            return Placement(x: 0.36, y: 0.59, zoom: 1.38, focus: true)
        }
        return Placement(x: 0.30, y: 0.50, zoom: 1.08, focus: true)
    }
}

enum HybridClock {
    /// The observation and the cab run share most of the ruler. The coasts are short.
    static let observationWeight = 0.62
    static let coastWeight = 0.06
    static let cabWeight = 0.26
    static let tailWeight = 0.06

    static func approachDate(timeline: Timeline) -> Date {
        FlybyEphemeris.bundled.flatMap {
            FlybyPath.closestApproach($0.samples, radiusKm: $0.document.radiusKm)?.date
        } ?? timeline.window.end
    }

    /// The Horizons closest approach, only when that instant is inside a playable span.
    static func playableApproach(timeline: Timeline) -> Date? {
        let date = approachDate(timeline: timeline)
        if date >= timeline.window.start, date < timeline.window.end { return date }
        if let cab = timeline.cabRun, date >= cab.start, date < cab.end { return date }
        return nil
    }

    static func pieces(timeline: Timeline) -> [RulerPiece] {
        let window = timeline.window
        let approach = approachDate(timeline: timeline)
        guard let cab = timeline.cabRun, cab.start > window.end, cab.end > cab.start else {
            if approach > window.end {
                return [
                    RulerPiece(start: window.start, end: window.end, weight: observationWeight),
                    RulerPiece(start: window.end, end: approach, weight: coastWeight + cabWeight + tailWeight),
                ]
            }
            return [RulerPiece(start: window.start, end: window.end, weight: 1)]
        }
        var rows = [
            RulerPiece(start: window.start, end: window.end, weight: observationWeight),
            RulerPiece(start: window.end, end: cab.start, weight: coastWeight),
            RulerPiece(start: cab.start, end: cab.end, weight: cabWeight),
        ]
        if approach > cab.end {
            rows.append(RulerPiece(start: cab.end, end: approach, weight: tailWeight))
        }
        return rows
    }

    static func fraction(date: Date, timeline: Timeline?) -> Double {
        guard let timeline else { return 0 }
        let rows = pieces(timeline: timeline)
        let total = rows.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        var used = 0.0
        for (index, piece) in rows.enumerated() {
            let duration = piece.end.timeIntervalSince(piece.start)
            let isLast = index == rows.count - 1
            if date < piece.end || isLast {
                let local: Double
                if duration <= 0 || date <= piece.start {
                    local = 0
                } else if date >= piece.end {
                    local = 1
                } else {
                    local = date.timeIntervalSince(piece.start) / duration
                }
                return min(1, max(0, (used + piece.weight * local) / total))
            }
            used += piece.weight
        }
        return 1
    }

    static func date(atFraction fraction: Double, timeline: Timeline?) -> Date? {
        guard let timeline else { return nil }
        let rows = pieces(timeline: timeline)
        let total = rows.reduce(0) { $0 + $1.weight }
        guard total > 0, let first = rows.first else { return nil }
        let target = min(1, max(0, fraction)) * total
        var used = 0.0
        for (index, piece) in rows.enumerated() {
            let next = used + piece.weight
            let isLast = index == rows.count - 1
            if target <= next || isLast {
                let local = piece.weight > 0 ? (target - used) / piece.weight : 0
                let duration = piece.end.timeIntervalSince(piece.start)
                return piece.start.addingTimeInterval(duration * min(1, max(0, local)))
            }
            used = next
        }
        return first.start
    }

    static func openingLine(window: TimeSpan) -> String {
        let clock = Stamp.clock(window.startUTC)
        let seconds = max(0, Int(window.end.timeIntervalSince(window.start).rounded()))
        let minutes = seconds / 60
        let remain = seconds % 60
        let duration = remain == 0 ? "\(minutes) min" : "\(minutes) min \(remain) s"
        return "\(clock) UTC · \(duration)"
    }
}

struct RulerPiece: Equatable {
    var start: Date
    var end: Date
    var weight: Double
}

/// One inset for the rail, the ticks, the needle, `y`, and `date(atY:)`.
/// The ruler label's time line is centered on its tick. The name hangs below that line.
enum RulerLabelMarks {
    /// Named ruler rows. Each date gets a tick, including a quote that is not a `MilestoneList` row.
    static let aristarchus = "2026-04-06T19:33:02.700Z"
    static let aristarchusLine = "2026-04-06T19:36:05.938Z"
    static let reiner = "2026-04-06T19:40:57.609Z"

    static func dates(timeline: Timeline?, approach: Date?) -> [Date] {
        let quotes = [aristarchus, aristarchusLine, reiner]
        var dates = quotes.compactMap { utc in timeline?.lines.first { $0.utc == utc }?.date }
        if let approach {
            dates.append(approach)
        }
        return dates
    }
}

enum RulerLabelLayout {
    /// Minimum hit height. The time text itself is `timeBand` and stays centered on the tick.
    static let timeLine: CGFloat = 44
    static let timeBand: CGFloat = 16
    /// The name starts at the bottom of the time band and hangs below it.
    static let nameOffset: CGFloat = 16
    static let nameLine: CGFloat = 14
    /// From the time-line center to the bottom of the name.
    static var nameTail: CGFloat { nameOffset - timeBand / 2 + nameLine }

    /// Keeps the time line on the rail. The rail inset is 16 pt, so clamping to half of the 44 pt hit target sat 6 pt off the tick.
    static func timeCenter(tick: CGFloat, height: CGFloat, safeArea: CGFloat = 0) -> CGFloat {
        let low = RulerMetrics.topInset
        let high = max(low, height - RulerMetrics.bottomInset(safeArea: safeArea))
        return min(max(low, tick), high)
    }

    static func nameTop(center: CGFloat) -> CGFloat {
        center - timeBand / 2 + nameOffset
    }
}

/// Hit target under a ruler label. It grows downward from the time band so it does not cover the name above.
private struct RulerHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        var hit = rect
        hit.size.height = max(rect.height, RulerLabelLayout.timeLine)
        return Path(hit)
    }
}

enum RulerMetrics {
    static let topInset: CGFloat = 16
    static let bottomInset: CGFloat = 16

    static func bottomInset(safeArea: CGFloat) -> CGFloat {
        // The name hangs past the 16 pt rail padding. Leave room for it above the safe edge.
        max(bottomInset, RulerLabelLayout.nameTail) + max(0, safeArea)
    }

    static func trackHeight(_ height: CGFloat, safeArea: CGFloat = 0) -> CGFloat {
        max(1, height - topInset - bottomInset(safeArea: safeArea))
    }

    static func y(fraction: Double, height: CGFloat, safeArea: CGFloat = 0) -> CGFloat {
        topInset + CGFloat(min(1, max(0, fraction))) * trackHeight(height, safeArea: safeArea)
    }

    static func fraction(y: CGFloat, height: CGFloat, safeArea: CGFloat = 0) -> Double {
        let track = trackHeight(height, safeArea: safeArea)
        return Double(min(1, max(0, (y - topInset) / track)))
    }
}

enum FrameOptics {
    /// "Window 2 · 400 mm" when the frame's label carries a window and a focal length.
    static func line(_ frame: Frame) -> String? {
        guard let window = frame.window, !window.isEmpty, let mm = frame.focalLengthMM, mm > 0 else { return nil }
        let whole = mm.rounded()
        let digits = abs(mm - whole) < 0.05 ? String(format: "%.0f", whole) : String(format: "%.1f", mm)
        return "Window \(window) · \(digits) mm"
    }
}

/// Keeps the last decoded frame on screen until the next file has a bitmap.
/// A cache miss must not clear the pane.
struct StableFramePhoto<Content: View>: View {
    @EnvironmentObject private var model: PlaybackModel
    var frame: Frame?
    var maxPixel: CGFloat
    @ViewBuilder var content: (UIImage, Frame) -> Content
    @State private var heldImage: UIImage?
    @State private var heldFrame: Frame?

    var body: some View {
        let live = decoded
        let shown = live ?? held
        Group {
            if let shown {
                content(shown.image, shown.frame)
            }
        }
        .onAppear { adopt(live) }
        .onChange(of: model.frameCacheEpoch) { _, _ in
            adopt(decoded)
            if decoded == nil, let frame {
                model.prefetch(frame, maxPixel: maxPixel)
            }
        }
        .onChange(of: frame?.file) { _, _ in
            adopt(decoded)
            if decoded == nil, let frame {
                model.prefetch(frame, maxPixel: maxPixel)
            }
        }
    }

    private var decoded: (image: UIImage, frame: Frame)? {
        guard let frame, let image = model.photo(frame, maxPixel: maxPixel) else { return nil }
        return (image, frame)
    }

    private var held: (image: UIImage, frame: Frame)? {
        guard let heldImage, let heldFrame else { return nil }
        return (heldImage, heldFrame)
    }

    private func adopt(_ live: (image: UIImage, frame: Frame)?) {
        guard let live else { return }
        heldImage = live.image
        heldFrame = live.frame
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var compact: Bool
    var includeCredit: Bool
    var identifier: String = "window-caption"
    /// Closed caption sharing the stage with the closest-approach card. It shrinks into
    /// the height it is offered instead of drawing through the card.
    var fitOfferedHeight: Bool = false

    /// Panel quotes stay at two lines at the default size. Accessibility sizes let the
    /// open-panel italic quote grow with Dynamic Type; the column scrolls. The closed
    /// caption at those sizes stays capped at three so the stage stays on the phone.
    /// The full line remains in Lines.
    private var quoteLineLimit: Int? {
        if fitOfferedHeight {
            return 3
        }
        if compact {
            if dynamicTypeSize.isAccessibilitySize {
                return nil
            }
            return 2
        }
        if dynamicTypeSize.isAccessibilitySize {
            return 3
        }
        return nil
    }

    /// The open panel at an accessibility size uses the scaled italic face and wraps.
    /// The closed caption at those sizes still shrinks into its cap. Default type
    /// keeps the natural size: the closed caption is uncapped, and the panel quote is two lines.
    private var quoteUsesNaturalHeight: Bool {
        if fitOfferedHeight {
            return false
        }
        if compact, dynamicTypeSize.isAccessibilitySize {
            return true
        }
        return !dynamicTypeSize.isAccessibilitySize
    }

    private var line: TranscriptLine? {
        LyricFocus.focus(at: model.utc, track: model.trackID, lines: model.timeline?.lines ?? []).current
    }

    private var frame: Frame? {
        HybridFrames.shown(at: model.utc, side: model.window, timeline: model.timeline, span: model.activeSpan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if let line {
                if let name = SpeakerLabel.display(line.speaker) {
                    speakerName(name)
                }
                TranscriptLineText(
                    text: line.text,
                    font: HybridFont.display(compact ? 15 : 28, relativeTo: compact ? .subheadline : .title2, italic: true),
                    color: HybridColor.cream,
                    annotationColor: HybridColor.dim,
                    // The panel column is about 198 pt wide on a 402×874 phone. Two lines
                    // are the tallest quote that leaves the clock and the transport fully
                    // visible above the window pills. The longest bundled line is ten lines
                    // at that width, so a taller cap would push the pills into Lines.
                    lineLimit: quoteLineLimit,
                    minimumScaleFactor: quoteUsesNaturalHeight ? CGFloat(1) : CGFloat(0.5)
                )
                .fixedSize(horizontal: false, vertical: quoteUsesNaturalHeight)
            }
            if let frame {
                frameIdentity(frame)
            }
            if includeCredit {
                CreditLine()
            }
        }
        .shadow(color: .black.opacity(0.65), radius: compact ? 0 : 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// One line at every size. Accessibility sizes scale the word instead of breaking it.
    /// The closed caption sits on the photograph, so the name is cream on dark glass.
    /// Gold on a bright frame fails contrast.
    @ViewBuilder
    private func speakerName(_ name: String) -> some View {
        let text = Text(name.uppercased())
            .font(HybridFont.text(11, relativeTo: .caption2))
            .tracking(1.6)
            .foregroundStyle(compact ? HybridColor.gold : HybridColor.cream)
        if !compact {
            text
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        }
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                .accessibilityIdentifier("speaker-name")
        } else if dynamicTypeSize.isAccessibilitySize {
            text
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("speaker-name")
        } else {
            text
        }
    }

    /// Default type keeps the dim one-line id. Accessibility sizes may wrap it.
    /// The closed caption at those sizes sits on the bright Moon, so the id gets the
    /// same dark glass and shadow that keep the quote readable.
    @ViewBuilder
    private func frameIdentity(_ frame: Frame) -> some View {
        let label = Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC")
            .font(HybridFont.text(12, relativeTo: .caption))
        if !compact, dynamicTypeSize.isAccessibilitySize {
            label
                .foregroundStyle(HybridColor.cream)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        }
                }
                .shadow(color: .black.opacity(0.65), radius: 8, y: 2)
        } else if dynamicTypeSize.isAccessibilitySize {
            label
                .foregroundStyle(HybridColor.dim)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            label
                .foregroundStyle(HybridColor.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ControlPanel: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var height: CGFloat
    var safeBottom: CGFloat
    var onClose: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: (_ translation: CGFloat, _ predicted: CGFloat, _ velocity: CGFloat) -> Void
    var onCrater: (CraterKind) -> Void
    @State private var about = false
    @State private var transcript = false
    @State private var moments = false
    @State private var suppressCloseTap = false

    var body: some View {
        column
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.bottom, safeBottom)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $about) { AboutView() }
        .sheet(isPresented: $transcript) { TranscriptSheet() }
        .sheet(isPresented: $moments) { MomentsSheet() }
    }

    /// Default type pins the quote above the window pills so a wrap cannot draw through them.
    /// Accessibility sizes (AX1–AX5) scale that quote, the pills, the crew row, and Lines
    /// past the 437 pt sheet, which used to collapse the clock scroller and hide play/pause.
    /// Those sizes put the whole column in one scroller, with the clock and transport first,
    /// so play/pause stays on screen and the rows below can scroll.
    @ViewBuilder
    private var column: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityColumn
        } else {
            standardColumn
        }
    }

    private var standardColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            handle
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    clocks
                    transport
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            panelCaption
            windowRow
                .fixedSize(horizontal: false, vertical: true)
            CrewRow()
                .fixedSize(horizontal: false, vertical: true)
            secondaryRow
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The scroll column takes the width the sheet proposes. Transport, pills, and
    /// Lines stack at these sizes so a long label cannot widen the column past the phone.
    private var accessibilityColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            handle
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        clocks
                        transport
                        panelCaption
                        windowRow
                        CrewRow()
                        secondaryRow
                        AccessibilityMomentList(onCrater: onCrater)
                    }
                    .padding(.bottom, 8)
                    .frame(width: geo.size.width, alignment: .leading)
                    .clipped()
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("panel-scroll")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var panelCaption: some View {
        DocumentaryCaption(compact: true, includeCredit: false, identifier: "panel-caption")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var handle: some View {
        Capsule()
            .fill(HybridColor.cream.opacity(0.72))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
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
                        onDragEnded(
                            value.translation.height,
                            value.predictedEndTranslation.height,
                            value.velocity.height
                        )
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
            if dynamicTypeSize.isAccessibilitySize {
                Text(time)
                    .font(HybridFont.display(32, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(HybridColor.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clocks.utc)
                        .font(HybridFont.text(13, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(HybridColor.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(clocks.met)
                        .font(HybridFont.text(13, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(HybridColor.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("mission-clock")
                .accessibilityLabel("\(clocks.utc) · \(clocks.met)")
            } else {
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
    }

    @ViewBuilder
    private var transport: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                skip(label: "−15s", access: "Skip back 15 seconds", identifier: "skip-back", seconds: -PlaybackModel.skipInterval)
                play
                skip(label: "+15s", access: "Skip forward 15 seconds", identifier: "skip-forward", seconds: PlaybackModel.skipInterval)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 22) {
                skip(label: "−15s", access: "Skip back 15 seconds", identifier: "skip-back", seconds: -PlaybackModel.skipInterval)
                play
                skip(label: "+15s", access: "Skip forward 15 seconds", identifier: "skip-forward", seconds: PlaybackModel.skipInterval)
            }
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
            skipLabel(label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(access)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func skipLabel(_ label: String) -> some View {
        let text = Text(label)
            .font(HybridFont.text(15, relativeTo: .body))
            .fontWeight(.semibold)
            .foregroundStyle(HybridColor.cream)
        if dynamicTypeSize.isAccessibilitySize {
            text
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            text
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    @ViewBuilder
    private var windowRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                windowButton("Window 2", side: .nikon, identifier: "window-nikon")
                windowButton("Window 3", side: .cab, identifier: "window-cab")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                windowButton("Window 2", side: .nikon, identifier: "window-nikon")
                windowButton("Window 3", side: .cab, identifier: "window-cab")
            }
        }
    }

    private func windowButton(_ title: String, side: WindowSide, identifier: String) -> some View {
        let selected = model.window == side
        return Button {
            model.setWindow(side)
        } label: {
            windowButtonLabel(title, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }

    @ViewBuilder
    private func windowButtonLabel(_ title: String, selected: Bool) -> some View {
        let text = Text(title)
            .font(HybridFont.text(13, relativeTo: .footnote))
            .fontWeight(.medium)
            .foregroundStyle(selected ? HybridColor.ink : HybridColor.dim)
        if dynamicTypeSize.isAccessibilitySize {
            text
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background {
                    Capsule().fill(selected ? HybridColor.cream.opacity(0.92) : Color.white.opacity(0.06))
                }
        } else {
            text
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background {
                    Capsule().fill(selected ? HybridColor.cream.opacity(0.92) : Color.white.opacity(0.06))
                }
        }
    }

    @ViewBuilder
    private var secondaryRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                textButton("Lines", identifier: "lines-button") { transcript = true }
                textButton("Moments", identifier: "moments-button") { moments = true }
                textButton("About", identifier: "about-button") { about = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                textButton("Lines", identifier: "lines-button") { transcript = true }
                textButton("Moments", identifier: "moments-button") { moments = true }
                textButton("About", identifier: "about-button") { about = true }
            }
        }
    }

    private func textButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            textButtonLabel(title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func textButtonLabel(_ title: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
                .font(HybridFont.text(15, relativeTo: .subheadline))
                .fontWeight(.semibold)
                .foregroundStyle(HybridColor.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            ZStack {
                Color.clear.frame(width: 44, height: 44)
                Text(title)
                    .font(HybridFont.text(15, relativeTo: .subheadline))
                    .fontWeight(.semibold)
                    .foregroundStyle(HybridColor.cream)
                    .padding(.horizontal, 4)
            }
            .fixedSize()
        }
    }
}

/// The four rail moments, stacked. Time sits on its own line above the name so a
/// large type size cannot draw one through the other or past the phone.
struct AccessibilityMomentList: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onCrater: (CraterKind) -> Void

    private var lineGap: CGFloat {
        switch dynamicTypeSize {
        case .accessibility1:
            return 6
        case .accessibility2:
            return 8
        case .accessibility3:
            return 10
        case .accessibility4:
            return 12
        case .accessibility5:
            return 16
        case .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge:
            return 8
        @unknown default:
            return 8
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: lineGap) {
            if let line = quote(RulerLabelMarks.aristarchus) {
                momentRow(time: Stamp.clock(line.utc), name: "Aristarchus", identifier: "milestone-aristarchus") {
                    onCrater(.aristarchus)
                }
            }
            if let line = quote(RulerLabelMarks.aristarchusLine) {
                momentRow(time: Stamp.clock(line.utc), name: "Aristarchus line", identifier: "milestone-wiseman") {
                    model.showFlyby()
                    model.seek(toLine: line)
                }
            }
            if let line = quote(RulerLabelMarks.reiner) {
                momentRow(time: Stamp.clock(line.utc), name: "Reiner Gamma", identifier: "milestone-reiner") {
                    onCrater(.reiner)
                }
            }
            if let approach = approachDate {
                let time = ClockMath.utcText(approach).replacingOccurrences(of: " UTC", with: "")
                if let landing = model.timeline.flatMap({ ClosestApproachLanding.make(timeline: $0) }) {
                    momentRow(
                        time: time,
                        name: "Closest approach",
                        identifier: "milestone-approach",
                        hint: landing.gap
                    ) {
                        model.showClosestApproach()
                    }
                } else {
                    momentRow(
                        time: time,
                        name: "Closest approach",
                        identifier: "milestone-approach",
                        hint: ClosestApproachLanding.missingNote() ?? "No crew recording at closest approach",
                        informational: true
                    ) {
                        model.showClosestApproach()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quote(_ utc: String) -> TranscriptLine? {
        model.timeline?.lines.first { $0.utc == utc }
    }

    private var approachDate: Date? {
        guard let bundled = FlybyEphemeris.bundled else { return nil }
        return FlybyPath.closestApproach(bundled.samples, radiusKm: bundled.document.radiusKm)?.date
    }

    /// One VoiceOver stop. Playable rows are buttons. A closest-approach row that
    /// has no recording is not a button; the hint carries the explanation.
    @ViewBuilder
    private func momentRow(
        time: String,
        name: String,
        identifier: String,
        hint: String? = nil,
        informational: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let label = momentLabel(time: time, name: name, informational: informational)
        if informational {
            label
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(time), \(name)")
                .accessibilityIdentifier(identifier)
                .modifier(MomentHint(hint: hint))
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(time), \(name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
            .modifier(MomentHint(hint: hint))
        }
    }

    private func momentLabel(time: String, name: String, informational: Bool) -> some View {
        VStack(alignment: .leading, spacing: lineGap) {
            Text(time)
                .font(HybridFont.text(13, relativeTo: .caption).monospacedDigit())
                .fontWeight(.regular)
                .foregroundStyle(informational ? HybridColor.dim : HybridColor.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(name)
                .font(nameFont(informational: informational))
                .fontWeight(informational ? .regular : .bold)
                .foregroundStyle(informational ? HybridColor.dim : HybridColor.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func nameFont(informational: Bool) -> Font {
        let font = HybridFont.text(15, relativeTo: .subheadline)
        return informational ? font.italic() : font
    }
}

/// VoiceOver hint for one moment. Empty hints are left off so other rows stay quiet.
private struct MomentHint: ViewModifier {
    var hint: String?

    func body(content: Content) -> some View {
        if let hint, !hint.isEmpty {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

struct FlybyRuler: View {
    @EnvironmentObject private var model: PlaybackModel
    var safeBottom: CGFloat = 0
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
                // 44 pt wide. The labels sit above this strip, so a mark keeps its tap.
                Color.clear
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(scrub(height: height))
                    .accessibilityElement()
                    .accessibilityLabel("Flyby timeline")
                    .accessibilityValue(ClockMath.utcText(model.utc))
                    .accessibilityAdjustableAction { direction in
                        model.accessibilityAdjust(direction)
                    }
                labelColumn(height: height, width: geo.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(width: 1, height: RulerMetrics.trackHeight(height, safeArea: safeBottom))
                .padding(.trailing, 18)
                .offset(y: RulerMetrics.topInset)
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
            ForEach(RulerLabelMarks.dates(timeline: timeline, approach: approachDate), id: \.timeIntervalSinceReferenceDate) { date in
                Capsule()
                    .fill(HybridColor.cream.opacity(0.9))
                    .frame(width: 10, height: 1)
                    .padding(.trailing, 14)
                    .offset(y: y(date, height: height))
            }
            Capsule()
                .fill(HybridColor.cream)
                .frame(width: 22, height: 2)
                .padding(.trailing, 10)
                .offset(y: y(model.utc, height: height) - 1)
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

    private func labelColumn(height: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let line = quote(utc: RulerLabelMarks.aristarchus) {
                placed(at: line.date, height: height, width: width) {
                    labelButton(time: Stamp.clock(line.utc), name: "Aristarchus", now: isNow(line.date), identifier: "milestone-aristarchus") {
                        onCrater(.aristarchus)
                    }
                }
            }
            if let line = quote(utc: RulerLabelMarks.aristarchusLine) {
                placed(at: line.date, height: height, width: width) {
                    labelButton(time: Stamp.clock(line.utc), name: "Aristarchus line", now: isNow(line.date), identifier: "milestone-wiseman") {
                        model.showFlyby()
                        model.seek(toLine: line)
                    }
                }
            }
            if let line = quote(utc: RulerLabelMarks.reiner) {
                placed(at: line.date, height: height, width: width) {
                    labelButton(time: Stamp.clock(line.utc), name: "Reiner Gamma", now: isNow(line.date), identifier: "milestone-reiner") {
                        onCrater(.reiner)
                    }
                }
            }
            if let approach = approachDate {
                placed(at: approach, height: height, width: width) {
                    approachMark(approach)
                }
            }
        }
    }

    private func placed<Label: View>(at date: Date, height: CGFloat, width: CGFloat, @ViewBuilder label: () -> Label) -> some View {
        let gutter: CGFloat = 36
        let labelWidth = max(96, width - gutter - 4)
        let centerX = width - gutter - labelWidth / 2
        let tick = y(date, height: height)
        // The time line, not the name under it, is centered on the tick.
        // The hit target is 44 pt and hangs below that line.
        let timeCenter = RulerLabelLayout.timeCenter(tick: tick, height: height, safeArea: safeBottom)
        let hit = RulerLabelLayout.timeLine
        let centerY = timeCenter + (hit - RulerLabelLayout.timeBand) / 2
        return label()
            .frame(width: labelWidth, height: hit, alignment: .topTrailing)
            .contentShape(Rectangle())
            .position(x: centerX, y: centerY)
    }

    private func labelButton(
        time: String,
        name: String,
        now: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rulerLabel(time: time, name: name, now: now)
                .contentShape(RulerHitShape())
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

    /// Closest approach from the Horizons table. The tap opens the nearest real
    /// frame and recording and labels the gap. With no media in either span, the
    /// mark is a quieter note and the card explains the table.
    @ViewBuilder
    private func approachMark(_ date: Date) -> some View {
        let time = ClockMath.utcText(date).replacingOccurrences(of: " UTC", with: "")
        if let landing = model.timeline.flatMap({ ClosestApproachLanding.make(timeline: $0) }) {
            labelButton(
                time: time,
                name: "Closest approach",
                now: isNow(landing.date),
                identifier: "milestone-approach"
            ) {
                model.showClosestApproach()
            }
            .accessibilityHint(landing.gap)
        } else {
            rulerLabel(time: time, name: "Closest approach", now: false)
                .contentShape(RulerHitShape())
                .onTapGesture { model.showClosestApproach() }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("milestone-approach")
                .accessibilityLabel("Closest approach")
                .accessibilityHint(ClosestApproachLanding.missingNote() ?? "No crew recording at closest approach")
        }
    }

    private func y(_ date: Date, height: CGFloat) -> CGFloat {
        RulerMetrics.y(
            fraction: HybridClock.fraction(date: date, timeline: model.timeline),
            height: height,
            safeArea: safeBottom
        )
    }

    private func rulerLabel(time: String, name: String, now: Bool) -> some View {
        Text(time)
            .font(HybridFont.text(11, relativeTo: .caption2).monospacedDigit())
            .fontWeight(.semibold)
            .foregroundStyle(now ? HybridColor.gold : HybridColor.cream)
            .frame(maxWidth: .infinity, minHeight: RulerLabelLayout.timeBand, alignment: .trailing)
            .frame(maxWidth: .infinity, minHeight: RulerLabelLayout.timeLine, alignment: .top)
            .overlay(alignment: .topTrailing) {
                Text(name)
                    .font(HybridFont.text(11, relativeTo: .caption2))
                    .foregroundStyle(now ? HybridColor.gold : HybridColor.cream)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, RulerLabelLayout.nameOffset)
            }
    }

    private func scrub(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let date = date(atY: value.location.y, height: height) else { return }
                if !model.scrubbing { model.beginScrub() }
                model.scrubRuler(to: date)
            }
            .onEnded { value in
                // A fast flick's finger can still be inside the span while the predicted end is past it.
                let predicted = date(atY: value.predictedEndLocation.y, height: height)
                if let predicted {
                    if !model.scrubbing { model.beginScrub() }
                    model.scrubRuler(to: predicted)
                }
                model.endScrub(markEnd: false)
            }
    }

    private func date(atY y: CGFloat, height: CGFloat) -> Date? {
        HybridClock.date(
            atFraction: RulerMetrics.fraction(y: y, height: height, safeArea: safeBottom),
            timeline: model.timeline
        )
    }
}

struct CraterPage: View {
    @EnvironmentObject private var model: PlaybackModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var kind: CraterKind
    var frame: Frame?
    var namespace: Namespace.ID
    var maxPixel: CGFloat
    var onClose: () -> Void
    @State private var showsData = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if dynamicTypeSize.isAccessibilitySize {
                        OrionReadout(date: frame?.date ?? model.utc, fillsWidth: true)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("orion-readout")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text(kind.kicker.uppercased())
                            .font(HybridFont.text(11, relativeTo: .caption2))
                            .tracking(1.6)
                            .foregroundStyle(HybridColor.gold)
                        Text(kind.title)
                            .font(HybridFont.display(40, relativeTo: .largeTitle))
                            .foregroundStyle(HybridColor.cream)
                        if let site {
                            Text("\(hemisphere(site.latitude, positive: "N", negative: "S")) · \(hemisphere(site.longitudeEast, positive: "E", negative: "W"))")
                                .font(HybridFont.text(15, relativeTo: .subheadline))
                                .foregroundStyle(HybridColor.cream)
                        }
                        if let card {
                            Text(card.body)
                                .font(HybridFont.display(22, relativeTo: .title3))
                                .foregroundStyle(HybridColor.cream)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("crater-why")
                        }
                        if let quote {
                            TranscriptLineText(
                                text: quote.text,
                                font: HybridFont.display(18, relativeTo: .body, italic: true),
                                color: HybridColor.cream,
                                annotationColor: HybridColor.dim
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            Text(SpeakerLabel.heading(speaker: quote.speaker, clock: "\(Stamp.clock(quote.utc)) UTC"))
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
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 32, height: 32)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HybridColor.cream)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.top, 54)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("close-crater")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("crater-page")
    }

    @ViewBuilder
    private var header: some View {
        ZStack(alignment: .bottom) {
            HybridColor.ground
            StableFramePhoto(frame: frame, maxPixel: maxPixel) { image, shown in
                let place = HybridFrames.placement(shown)
                PlacedPhoto(
                    image: image,
                    objectX: place.x,
                    objectY: place.y,
                    zoom: place.zoom,
                    focus: place.focus
                )
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .clipped()
                .matchedGeometryEffect(id: "flyby-photo", in: namespace)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(FrameSelection.photoAccessLabel(shown))
                .accessibilityAddTraits(.isImage)
            }
            LinearGradient(
                colors: [.clear, HybridColor.ground.opacity(0.2), HybridColor.ground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            TrackMapView(
                date: frame?.date ?? model.utc,
                emphasized: kind.siteID,
                showsReadout: !dynamicTypeSize.isAccessibilitySize
            )
                .frame(maxWidth: .infinity, maxHeight: 168)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
        .frame(height: 420)
        .clipped()
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showsData.toggle()
            } label: {
                HStack {
                    Text("About this data")
                        .font(HybridFont.text(15, relativeTo: .subheadline))
                        .fontWeight(.semibold)
                        .foregroundStyle(HybridColor.cream)
                    Spacer(minLength: 8)
                    Text(showsData ? "-" : "+")
                        .font(HybridFont.text(18, relativeTo: .body))
                        .foregroundStyle(HybridColor.dim)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("about-this-data")
            .accessibilityLabel("About this data")
            if let frame {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(frame.nasaID) · \(Stamp.clock(frame.utc)) UTC")
                        .accessibilityIdentifier("crater-photo-id")
                    if let optics = FrameOptics.line(frame) {
                        Text(optics)
                            .accessibilityIdentifier("crater-optics")
                    }
                    Text(frame.credit)
                }
                .font(HybridFont.text(13, relativeTo: .footnote))
                .foregroundStyle(HybridColor.dim)
                .fixedSize(horizontal: false, vertical: true)
                CreditLine()
            }
            if showsData {
                VStack(alignment: .leading, spacing: 10) {
                    if let site {
                        Text(site.source)
                    }
                    if let aim {
                        Text("Lunar Targeting Plan aim \(hemisphere(aim.lat, positive: "N", negative: "S")) · \(hemisphere(aim.lon, positive: "E", negative: "W")). Not the USGS center.")
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func hemisphere(_ value: Double, positive: String, negative: String) -> String {
        String(format: "%.2f° %@", abs(value), value >= 0 ? positive : negative)
    }
}

/// The stage ignores the safe area, so a geometry reader on it reports a zero bottom inset.
/// This reads the window inset instead and reports it once the view is in a window.
struct WindowSafeAreaReader: UIViewRepresentable {
    var onBottom: @MainActor (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onBottom = onBottom
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.onBottom = onBottom
        view.report()
    }

    @MainActor
    final class Probe: UIView {
        var onBottom: (@MainActor (CGFloat) -> Void)?
        private var reported: CGFloat = -1

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        func report() {
            guard let window else { return }
            let bottom = window.safeAreaInsets.bottom
            guard bottom != reported else { return }
            reported = bottom
            let send = onBottom
            Task { @MainActor in
                send?(bottom)
            }
        }
    }
}

/// Bottom inset of the key window, read synchronously so the first frame is not laid out at 0.
@MainActor
enum WindowSafeArea {
    static var bottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.keyWindow ?? scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
                return window.safeAreaInsets.bottom
            }
        }
        return 0
    }
}

/// Card on top, caption in whatever height remains. The caption is not offered the card's rect.
private struct ApproachColumn: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let card = subviews.first else { return }
        let width = bounds.width
        let cardSize = card.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let cardHeight = min(max(0, cardSize.height), bounds.height)
        card.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: ProposedViewSize(width: width, height: cardHeight)
        )
        guard subviews.count > 1 else { return }
        let captionY = bounds.minY + cardHeight + spacing
        let captionHeight = max(0, bounds.maxY - captionY)
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: captionY),
            proposal: ProposedViewSize(width: width, height: captionHeight)
        )
    }
}

/// Closed-caption clearance. The collapsed Controls strip is the cue plus its bottom inset.
/// The caption used to stop 12 pt short of that strip, so the credit pill covered it.
enum ClosedCaptionMetrics {
    /// Room above the accessibility caption so it stays below the status bar.
    static let topClearance: CGFloat = 160
    /// Same inset as the collapsed Controls button.
    static let controlsBottomInset: CGFloat = 76
    static let handleHeight: CGFloat = 4
    static let cueSpacing: CGFloat = 8
    static let progressHeight: CGFloat = 8
    static let cueVerticalPadding: CGFloat = 12
    /// Handle, gap, progress, and the cue's vertical padding.
    static var controlsStripHeight: CGFloat {
        cueVerticalPadding + handleHeight + cueSpacing + progressHeight + cueVerticalPadding
    }
    /// Bottom of the credit sits on the top of the Controls strip.
    static var bottomClearance: CGFloat { controlsBottomInset + controlsStripHeight }
}

/// The scrollable part of the sheet keeps its height. The home-indicator inset is added
/// outside that number, so the padding does not push the caption below the fold.
enum PanelMetrics {
    static func contentHeight(screenHeight: CGFloat) -> CGFloat {
        min(460, max(340, screenHeight * 0.5))
    }

    static func sheetHeight(screenHeight: CGFloat, safeBottom: CGFloat) -> CGFloat {
        contentHeight(screenHeight: screenHeight) + max(0, safeBottom)
    }
}

/// Small credit kept on every photograph. Its own element, so a crater page
/// query can find `photo-credit` beside the picture.
struct CreditLine: View {
    var body: some View {
        Text("Credit: NASA/Artemis II Crew")
            .font(HybridFont.text(11, relativeTo: .caption2))
            .foregroundStyle(HybridColor.cream)
            .lineLimit(2)
            .minimumScaleFactor(0.4)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("photo-credit")
            .accessibilityLabel("Credit: NASA/Artemis II Crew")
    }
}
