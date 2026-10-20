import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

/// Tokens owned for the life of the player. Main-actor isolated, so it is Sendable
/// and the model's nonisolated deinit can hand it back to the main actor to tear down.
@MainActor
private final class PlaybackLifetime {
    var engineObserver: NSObjectProtocol?
    var displayLink: CADisplayLink?
    var commands: [(MPRemoteCommand, Any)] = []

    nonisolated init() {}

    func tearDown() {
        if let engineObserver {
            NotificationCenter.default.removeObserver(engineObserver)
            self.engineObserver = nil
        }
        displayLink?.invalidate()
        displayLink = nil
        for (command, token) in commands {
            command.removeTarget(token)
        }
        commands.removeAll()
    }
}

/// One master clock. The crew recording is the time source while a real file
/// is playing. Gaps, including the opening seconds before the first file,
/// advance on the wall clock and stay silent. Nothing is synthesized.
@MainActor
final class PlaybackModel: NSObject, ObservableObject {
    static let spatialDefaultsKey = "artemis.spatial"
    /// Lock-screen skip and the dock skips use this same interval.
    /// Nonisolated so the remote-command `??` autoclosure can read it.
    nonisolated static let skipInterval: TimeInterval = ClockNudge.interval

    private(set) var timeline: Timeline?
    private(set) var loadError: String?

    @Published var utc = Date(timeIntervalSince1970: 0)
    @Published var playing = false
    @Published var window: WindowSide = .nikon
    @Published var trackID = "pcd3"
    @Published var crewID = "Wiseman"
    @Published var range: MissionRange = .flyby
    @Published var spatial = false
    @Published var arrived = false
    /// Set when a playable span reaches its own end. A pause in the middle does not set it.
    @Published var ended = false
    @Published var engineFailed = false
    /// The hybrid stage reads the shipped frame. `maxPixel` caps the decode.
    /// Lock-screen art still asks for the 720 sibling on its own.
    @Published var phoneImages = false
    /// Bumped when a prefetched frame lands in the cache. Views read this and stay cache-only.
    @Published private(set) var frameCacheEpoch = 0

    /// Created on first use. The unit-test host never reads these, so it never builds an audio graph.
    private lazy var engine = AVAudioEngine()
    private lazy var player = AVAudioPlayerNode()
    private lazy var environment = AVAudioEnvironmentNode()
    private var audioFile: AVAudioFile?
    private var currentFile: String?
    private var scheduledStart: TimeInterval = 0
    private var holdSeconds: TimeInterval = 0
    /// Silent wait before a future-scheduled file. The node counts it as play time.
    private var scheduledLead: TimeInterval = 0
    /// Host time when that future-scheduled file should become audible.
    private var audibleHostSeconds: TimeInterval?
    /// Mission time when a file scheduled in the future should become audible.
    private var holdUntil: Date?
    private var scheduleGeneration = 0
    private var usingEnvironment = false
    private var graphReady = false
    private var pan: Float = 0
    private var rebuilding = false
    /// The mission scrubber owns the clock until the finger lifts.
    private(set) var scrubbing = false
    private var resumeAfterInterrupt = false
    private var commandsInstalled = false
    private var lastWall: CFTimeInterval?
    private var lastInfoSecond = Int.min
    private var lastInfoPlaying = false
    private var lastArtID = ""
    /// Seek and crew or span switches. Consumed by the next activity push.
    private var activityEvent = false
    private var lastActivityPush = Date.distantPast
    private var lastActivitySpeaker = ""
    private var lastActivityPlaying: Bool?
    private var lastActivityEnded = false
    private var lastActivityWasMissing = false
    private static let activityPushInterval: TimeInterval = 15
    /// Unit tests set this so the shipping activity policy runs without the audio graph or Now Playing.
    var postsLiveActivityWhileSkippingAudio = false
    /// Set with the scene. The background span-end path reads it when the unit-test host has no display link.
    private var displayClockPaused = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var unavailableFiles = Set<String>()
    nonisolated private let lifetime = PlaybackLifetime()

    override init() {
        super.init()
        spatial = UserDefaults.standard.bool(forKey: Self.spatialDefaultsKey)
        loadTimeline()
        MediaStore.observeMemoryWarning()
        guard !RuntimeHost.isUnitTestHost else { return }
        attachGraph()
        configureEnvironment()
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        observeNotifications()
        observeEngineConfiguration()
    }

    deinit {
        let lifetime = self.lifetime
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                lifetime.tearDown()
            }
        } else {
            Task { @MainActor in
                lifetime.tearDown()
            }
        }
        NotificationCenter.default.removeObserver(self)
    }

    var activeSpan: TimeSpan? {
        if range == .cab, let cab = timeline?.cabRun { return cab }
        return timeline?.window
    }

    func segment(at date: Date) -> Segment? {
        timeline?.segments.first { segment in
            segment.track == trackID && date >= segment.start && date < segment.end
        }
    }

    // MARK: - Gate

    /// Activates the playback session inside the tap. Does not run at launch,
    /// so other audio is left alone until the viewer starts.
    func begin() {
        guard !arrived, timeline != nil else { return }
        if Self.opensAtSpanEnd(ProcessInfo.processInfo.arguments), let end = activeSpan?.end {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                arrived = true
                utc = end
                ended = true
                playing = false
            }
            return
        }
        guard !RuntimeHost.isUnitTestHost else {
            arrived = true
            return
        }
        FlybyLiveActivity.useSystemClient()
        do {
            try activateSpokenSession()
        } catch {
            engineFailed = true
        }
        arrived = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        installRemoteCommands()
        startDisplayLink()
        haptic.prepare()
        play()
    }

    /// UI tests pass `-seekToEnd` so the end card can be reached without dragging the path.
    /// Playing from that instant would rewind to the span start.
    nonisolated static func opensAtSpanEnd(_ arguments: [String]) -> Bool {
        arguments.contains("-seekToEnd")
    }

    /// `fromHold` reschedules the real file at the offset saved across an interruption.
    func play(fromHold: Bool = false) {
        guard timeline != nil else { return }
        if let end = activeSpan?.end, utc >= end, let start = activeSpan?.start {
            utc = start
            currentFile = nil
            holdUntil = nil
            holdSeconds = 0
        }
        playing = true
        resumeAfterInterrupt = false
        guard !RuntimeHost.isUnitTestHost else { return }
        guard !engineFailed else {
            refreshNowPlaying(force: true)
            return
        }
        if let armed = holdUntil, armed > utc, let segment = segmentForCurrentFile() {
            scheduleAtRealStart(segment, delay: armed.timeIntervalSince(utc))
            refreshNowPlaying(force: true)
            return
        }
        // Resume on a fresh schedule at the saved sample. Playing the old node
        // again would keep a host-time anchor that advanced through the pause.
        if (fromHold || !player.isPlaying), let file = audioFile, currentFile != nil {
            reschedule(file: file, at: max(0, holdSeconds))
        }
        do {
            try activateSpokenSession()
            if !engine.isRunning {
                try startEngine()
            }
        } catch {
            failEngine()
            return
        }
        followSegment()
        if let segment = segment(at: utc), currentFile == segment.file, audioFile != nil, !player.isPlaying {
            player.play()
        }
        refreshNowPlaying(force: true)
    }

    /// `user` is a pause the person asked for, including headphones coming off.
    /// That clears the interruption resume flag so a later `.shouldResume`
    /// does not start the recording again.
    func pause(user: Bool) {
        if !skipsAudio {
            let nodeWasPlaying = player.isPlaying
            let rendered = nodeWasPlaying ? renderedSeconds() : max(0, holdSeconds)
            let wait = audibleHostSeconds.map {
                PlaybackTiming.remainingWait(
                    nowHostSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()),
                    audibleHostSeconds: $0
                )
            }
            if nodeWasPlaying {
                holdSeconds = rendered
            }
            player.pause()
            audibleHostSeconds = nil
            scheduledLead = 0
            if let segment = segmentForCurrentFile() {
                let paused = PlaybackTiming.clockAfterPause(
                    segmentStart: segment.start,
                    segmentEnd: segment.end,
                    renderedSeconds: rendered,
                    holdSeconds: holdSeconds,
                    holdUntil: holdUntil,
                    utc: utc,
                    remainingWait: wait,
                    nodeWasPlaying: nodeWasPlaying
                )
                utc = paused.utc
                holdUntil = paused.holdUntil
                holdSeconds = paused.holdSeconds
                if paused.resetWallClock {
                    lastWall = nil
                }
            } else if nodeWasPlaying, rendered > 0 {
                holdUntil = nil
                lastWall = nil
            }
        }
        playing = false
        if user {
            resumeAfterInterrupt = false
        }
        // A mid-span pause keeps the activity and marks it paused, including a pause from
        // the lock screen, headphones, or an interruption. The span end dismisses it.
        if let end = activeSpan?.end, utc >= end {
            FlybyLiveActivity.scheduleEndAllImmediately()
        }
        refreshNowPlaying(force: true)
    }

    func toggle() {
        if playing { pause(user: true) } else { play() }
    }

    func setWindow(_ side: WindowSide) {
        guard window != side else { return }
        window = side
        haptic.impactOccurred()
    }

    func follow(_ member: CrewMember) {
        crewID = member.id
        guard member.track != trackID else { return }
        trackID = member.track
        reloadAtCurrentTime()
    }

    func cycleCrew() {
        guard let members = timeline?.crew, !members.isEmpty else { return }
        let index = members.firstIndex { $0.id == crewID } ?? -1
        let next = members[(index + 1) % members.count]
        crewID = next.id
        guard next.track != trackID else { return }
        trackID = next.track
        reloadAtCurrentTime()
    }

    func showCabRun() {
        guard timeline?.cabRun != nil else { return }
        if trackID != "pcd2" {
            trackID = "pcd2"
            if let member = timeline?.crew.first(where: { $0.track == "pcd2" }) {
                crewID = member.id
            }
        }
        range = .cab
        utc = timeline?.cabRun?.start ?? utc
        holdUntil = nil
        setWindow(.cab)
        reloadAtCurrentTime()
    }

    func showFlyby() {
        range = .flyby
        utc = timeline?.window.start ?? utc
        holdUntil = nil
        setWindow(.nikon)
        reloadAtCurrentTime()
    }

    func seek(to date: Date, markEnd: Bool = true) {
        guard let span = activeSpan else { return }
        activityEvent = true
        utc = MissionClock.clamp(date, to: span)
        let atEnd = markEnd && utc >= span.end
        ended = atEnd
        holdUntil = nil
        rebuilding = true
        defer { rebuilding = false }
        if atEnd {
            playing = false
            stopPlayer()
            FlybyLiveActivity.scheduleEndAllImmediately()
            refreshNowPlaying(force: true)
            return
        }
        if let segment = segment(at: utc) {
            if currentFile == segment.file, let file = audioFile {
                reschedule(file: file, at: utc.timeIntervalSince(segment.start))
                restartPlayerIfNeeded()
            } else {
                currentFile = nil
                audioFile = nil
                if playing { loadSegment(segment) }
            }
        } else {
            holdSeconds = 0
            stopPlayer()
        }
        refreshNowPlaying(force: true)
    }

    private func restartPlayerIfNeeded() {
        guard !skipsAudio else { return }
        guard playing, !engineFailed, audioFile != nil else { return }
        do {
            if !engine.isRunning {
                try startEngine()
            }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            failEngine()
        }
    }

    func seek(toLine line: TranscriptLine) {
        if line.track != trackID {
            trackID = line.track
            if timeline?.crew.contains(where: { $0.id == crewID && $0.track == line.track }) != true,
               let member = timeline?.crew.first(where: { $0.track == line.track }) {
                crewID = member.id
            }
            currentFile = nil
            audioFile = nil
        }
        if let span = activeSpan, line.date < span.start || line.date >= span.end {
            range = .flyby
            currentFile = nil
            audioFile = nil
        }
        playing = true
        holdUntil = nil
        seek(to: line.date)
        engagePlayback()
    }

    /// Moves the clock, the crew track, the window, and the recording together.
    func jump(to milestone: Milestone, markEnd: Bool = true) {
        guard let timeline else { return }
        let cue = MilestoneSeek.cue(
            for: milestone,
            timeline: timeline,
            range: range,
            trackID: trackID,
            window: window
        )
        if cue.range != range {
            range = cue.range
            currentFile = nil
            audioFile = nil
        }
        if cue.trackID != trackID {
            trackID = cue.trackID
            if timeline.crew.contains(where: { $0.id == crewID && $0.track == cue.trackID }) != true,
               let member = timeline.crew.first(where: { $0.track == cue.trackID }) {
                crewID = member.id
            }
            currentFile = nil
            audioFile = nil
        }
        if window != cue.window {
            setWindow(cue.window)
        }
        playing = true
        holdUntil = nil
        scrubbing = false
        seek(to: cue.date, markEnd: markEnd)
        if !ended {
            engagePlayback()
        }
    }

    func beginScrub() {
        scrubbing = true
        lastWall = nil
    }

    func scrub(toFraction fraction: Double) {
        guard scrubbing, let span = activeSpan else { return }
        let duration = span.end.timeIntervalSince(span.start)
        let date = span.start.addingTimeInterval(duration * min(1, max(0, fraction)))
        utc = MissionClock.clamp(date, to: span)
    }

    /// A ruler drag stops this far short of the span end. The last few seconds
    /// belong to playback, so releasing the ruler cannot sit on the edge where
    /// one display-link step walks off the end.
    static let scrubEndMargin: TimeInterval = 8

    /// Ruler drag. Stays strictly inside the active span, and at least
    /// `scrubEndMargin` short of the end. A date in the cab run, or on the
    /// span end, does not move the clock and does not change range.
    func scrubRuler(to date: Date) {
        guard scrubbing, let span = activeSpan else { return }
        guard date >= span.start, date < span.end else { return }
        let latest = span.end.addingTimeInterval(-Self.scrubEndMargin)
        utc = min(date, max(span.start, latest))
    }

    /// `markEnd` is false while the flyby ruler is exploring the coast past the
    /// observation window. Releasing there must not end the Live Activity.
    /// The launch argument and an explicit seek to the span end still do.
    func endScrub(markEnd: Bool = true) {
        guard scrubbing else { return }
        scrubbing = false
        lastWall = nil
        seek(to: utc, markEnd: markEnd)
    }

    /// Path drag. Playback stays running unless the finger lands on the span end.
    func beginPathScrub() {
        beginScrub()
    }

    func scrubPath(to date: Date) {
        guard let timeline else { return }
        guard let span = spanContaining(date, timeline: timeline) else { return }
        if !scrubbing {
            beginScrub()
        }
        if activeSpan?.start != span.start || activeSpan?.end != span.end {
            range = timeline.cabRun?.start == span.start ? .cab : .flyby
            currentFile = nil
            audioFile = nil
        }
        utc = MissionClock.clamp(date, to: span)
    }

    /// A time inside a real recording in this span. Silent gaps are not a place to land.
    private func recordedDate(near date: Date, in span: TimeSpan, timeline: Timeline) -> Date? {
        let clips = timeline.segments.filter { segment in
            segment.end > span.start && segment.start < span.end
        }
        guard !clips.isEmpty else { return nil }
        let preferred = clips.filter { $0.track == trackID }
        let pool = preferred.isEmpty ? clips : preferred
        if pool.contains(where: { date >= $0.start && date < $0.end }) {
            return date
        }
        var best: (date: Date, distance: TimeInterval)?
        for clip in pool {
            let start = max(clip.start, span.start)
            let end = min(clip.end, span.end)
            guard end > start else { continue }
            let landed = min(max(date, start), end.addingTimeInterval(-0.05))
            let distance = abs(landed.timeIntervalSince(date))
            if best == nil || distance < best!.distance {
                best = (landed, distance)
            }
        }
        return best?.date
    }

    func endPathScrub() {
        guard scrubbing else { return }
        if let span = activeSpan, utc >= span.end {
            utc = span.end
            endScrub()
            return
        }
        if let timeline, let span = activeSpan, let landed = recordedDate(near: utc, in: span, timeline: timeline) {
            if segment(at: landed) == nil,
               let track = timeline.segments.first(where: { landed >= $0.start && landed < $0.end })?.track,
               track != trackID {
                trackID = track
                if let member = timeline.crew.first(where: { $0.track == track }) {
                    crewID = member.id
                }
                currentFile = nil
                audioFile = nil
            }
            utc = landed
        }
        endScrub()
    }

    private func spanContaining(_ date: Date, timeline: Timeline) -> TimeSpan? {
        if let cab = timeline.cabRun, date >= cab.start, date <= cab.end {
            return cab
        }
        if date >= timeline.window.start, date <= timeline.window.end {
            return timeline.window
        }
        return nil
    }

    private func engagePlayback() {
        guard !skipsAudio else { return }
        guard playing, !engineFailed else { return }
        do {
            try activateSpokenSession()
            if !engine.isRunning {
                try startEngine()
            }
            if let segment = segment(at: utc), currentFile == segment.file, audioFile != nil, !player.isPlaying {
                player.play()
            }
        } catch {
            failEngine()
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: utc.addingTimeInterval(seconds))
    }

    /// VoiceOver adjustable action on the mission scrubber. A skip, not a scrub.
    func accessibilityAdjust(_ direction: AccessibilityAdjustmentDirection) {
        let nudge: ClockNudge?
        switch direction {
        case .increment:
            nudge = .forward
        case .decrement:
            nudge = .back
        @unknown default:
            nudge = nil
        }
        guard let nudge, !nudge.scrubs else { return }
        skip(by: nudge.seconds)
    }

    /// Lock-screen scrubber. `seconds` is elapsed time inside the active span.
    func seekElapsed(_ seconds: TimeInterval) {
        guard let span = activeSpan else { return }
        seek(to: span.start.addingTimeInterval(seconds))
    }

    /// Reconnects the real file through the environment node, or back to the
    /// dry mixer. The mission clock stays where it is. No bed, no tone.
    func setSpatial(_ enabled: Bool) {
        guard enabled != spatial else { return }
        spatial = enabled
        UserDefaults.standard.set(enabled, forKey: Self.spatialDefaultsKey)
        guard let file = audioFile else { return }
        let seconds = renderedSeconds()
        let wasPlaying = playing && (player.isPlaying || holdUntil != nil)
        let armed = holdUntil
        let armedSegment = segmentForCurrentFile()
        rebuilding = true
        defer { rebuilding = false }
        stopPlayer()
        engine.stop()
        graphReady = false
        usingEnvironment = false
        if let armed, armed > utc, let armedSegment {
            scheduleAtRealStart(armedSegment, delay: max(0, armed.timeIntervalSince(utc)))
            return
        }
        connectGraph(format: file.processingFormat)
        reschedule(file: file, at: seconds)
        do {
            try startEngine()
            if wasPlaying { player.play() }
        } catch {
            failEngine()
        }
    }

    func setSceneActive(_ active: Bool) {
        displayClockPaused = !active
        if active {
            lifetime.displayLink?.isPaused = false
            if !skipsAudio, holdUntil == nil, player.isPlaying, let segment = segmentForCurrentFile() {
                // Sample time, not host time, so a pause does not move the clock.
                utc = segment.start.addingTimeInterval(renderedSeconds())
                lastWall = nil
            }
        } else {
            lifetime.displayLink?.isPaused = true
            // Drop the last tick so unlocking does not add the whole locked interval
            // in one step and walk a scrub near the end off the span.
            lastWall = nil
            if playing {
                chainForward(from: utc)
            }
            // The display link will not tick in the background. Push the current state
            // once, including a pause, so the lock screen shows "Paused" before suspension.
            // Backgrounding itself does not end the activity.
            refreshNowPlaying(force: true)
        }
    }

    // MARK: - Graph

    private func loadTimeline() {
        let bundled = Bundle.main.url(forResource: "timeline", withExtension: "json", subdirectory: "DemoData")
            ?? Bundle.main.url(forResource: "timeline", withExtension: "json")
        guard let bundled else {
            loadError = "Timeline was not copied into the app."
            return
        }
        do {
            let parsed = try Timeline(data: Data(contentsOf: bundled))
            timeline = parsed
            utc = parsed.window.start
            if let first = parsed.crew.first {
                crewID = first.id
                trackID = first.track
            }
        } catch {
            loadError = "Timeline was not copied into the app."
        }
    }

    private func attachGraph() {
        engine.attach(player)
        engine.attach(environment)
    }

    private func configureEnvironment() {
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.reverbParameters.enable = false
        let attenuation = environment.distanceAttenuationParameters
        attenuation.distanceAttenuationModel = .linear
        attenuation.referenceDistance = 10
        attenuation.maximumDistance = 50
        attenuation.rolloffFactor = 0.1
        player.renderingAlgorithm = .equalPowerPanning
        player.volume = 1
    }

    /// Dry path plays the file unmodified. The environment path only moves
    /// that same file. The source sits inside the reference distance, so the
    /// linear rolloff does not change loudness.
    private func connectGraph(format: AVAudioFormat) {
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(environment)
        if spatial {
            engine.connect(player, to: environment, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: format)
            usingEnvironment = true
            pan = targetPan
            player.position = AVAudio3DPoint(x: pan, y: 0, z: -1.5)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            usingEnvironment = false
        }
        graphReady = true
    }

    private var targetPan: Float {
        window == .nikon ? -0.35 : 0.35
    }

    private func easePan() {
        let target = targetPan
        pan += (target - pan) * 0.15
        player.position = AVAudio3DPoint(x: pan, y: 0, z: -1.5)
    }

    private func failEngine() {
        playing = false
        holdUntil = nil
        engineFailed = true
        stopPlayer()
        FlybyLiveActivity.scheduleEndAllImmediately()
        refreshNowPlaying(force: true)
    }

    /// Invalidates a scheduled completion, then stops the node.
    /// Every `player.stop()` goes through here so a stale completion cannot move `utc`.
    private func stopPlayer() {
        scheduleGeneration += 1
        scheduledLead = 0
        audibleHostSeconds = nil
        guard !skipsAudio else { return }
        player.stop()
    }

    func noteFramesDecoded(file: String) {
        frameCacheEpoch += 1
        guard file == currentArtworkFile() else { return }
        refreshNowPlaying(force: true)
    }

    private func currentArtworkFile() -> String {
        if let frame = pair(for: window).current {
            return frame.file
        }
        return "images/art002e016184.webp"
    }

    private func reloadAtCurrentTime() {
        currentFile = nil
        audioFile = nil
        holdUntil = nil
        stopPlayer()
        if playing { followSegment() }
        activityEvent = true
        refreshNowPlaying(force: true)
    }

    private var skipsAudio: Bool { RuntimeHost.isUnitTestHost }

    private func followSegment() {
        guard !skipsAudio else { return }
        guard playing, !engineFailed, holdUntil == nil else { return }
        guard let segment = segment(at: utc) else {
            if player.isPlaying {
                holdSeconds = renderedSeconds()
                player.pause()
            }
            return
        }
        if currentFile != segment.file || (audioFile == nil && !unavailableFiles.contains(segment.file)) {
            loadSegment(segment)
        }
    }

    private func loadSegment(_ segment: Segment) {
        guard !skipsAudio else { return }
        if unavailableFiles.contains(segment.file) {
            currentFile = segment.file
            audioFile = nil
            stopPlayer()
            return
        }
        guard let url = MediaStore.url(for: segment.file) else {
            unavailableFiles.insert(segment.file)
            currentFile = segment.file
            audioFile = nil
            stopPlayer()
            return
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            unavailableFiles.insert(segment.file)
            currentFile = segment.file
            audioFile = nil
            stopPlayer()
            return
        }
        audioFile = file
        currentFile = segment.file
        let offset = max(0, utc.timeIntervalSince(segment.start))
        if !graphReady || usingEnvironment != spatial {
            let restart = engine.isRunning
            if restart {
                engine.stop()
            }
            connectGraph(format: file.processingFormat)
            if restart {
                do {
                    try startEngine()
                } catch {
                    failEngine()
                    return
                }
            }
        }
        reschedule(file: file, at: offset)
        guard playing else { return }
        do {
            if !engine.isRunning {
                try startEngine()
            }
            player.play()
        } catch {
            failEngine()
        }
    }

    private func reschedule(file: AVAudioFile, at seconds: TimeInterval, when: AVAudioTime? = nil, lead: TimeInterval = 0) {
        guard !skipsAudio else { return }
        stopPlayer()
        let generation = scheduleGeneration
        if let when, when.isHostTimeValid {
            audibleHostSeconds = AVAudioTime.seconds(forHostTime: when.hostTime)
            scheduledLead = max(0, lead)
        }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return }
        let clamped = max(0, seconds)
        let start = AVAudioFramePosition(clamped * rate)
        if start >= file.length {
            scheduledStart = clamped
            holdSeconds = clamped
            return
        }
        let remaining = file.length - start
        let count = AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max)))
        guard count > 0 else { return }
        let actual = Double(start) / rate
        scheduledStart = actual
        holdSeconds = actual
        let endSeconds = actual + Double(count) / rate
        // The audio thread calls this. It must not inherit MainActor isolation.
        player.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: count,
            at: when,
            completionHandler: { @Sendable [weak self] in
                Task { @MainActor in
                    guard let model = self, model.scheduleGeneration == generation else { return }
                    model.holdSeconds = endSeconds
                    model.segmentDidFinish()
                }
            }
        )
    }

    /// Test seam for the private clip-finished path. The audio graph stays unused.
    func finishCurrentClipForTest(file: String, renderedSeconds: TimeInterval) {
        currentFile = file
        holdSeconds = renderedSeconds
        segmentDidFinish()
    }

    /// Test seam for one private display-link step. No `CADisplayLink` is installed.
    func advanceDisplayLinkForTest(to timestamp: CFTimeInterval) {
        tickOnMain(timestamp)
    }

    /// The scheduled file reached its end. The display link is paused in the
    /// background, so the next real file has to be armed here.
    private func segmentDidFinish() {
        guard playing, !rebuilding, !engineFailed else { return }
        // The armed file has ended. Clear the pre-roll mark so the next file can chain
        // even though the display link never ran to clear it.
        holdUntil = nil
        guard let segment = segmentForCurrentFile() else { return }
        var nextUTC = segment.start.addingTimeInterval(holdSeconds)
        if let spanEnd = activeSpan?.end {
            nextUTC = min(nextUTC, spanEnd)
        }
        utc = nextUTC
        if let spanEnd = activeSpan?.end, utc >= spanEnd {
            ended = true
            // utc is already the span end, so pause dismisses the Live Activity.
            pause(user: true)
            return
        }
        chainForward(from: utc)
    }

    /// Plays the next real segment, or arms it at its own start time.
    /// A silent tail — the ruler dragged past the last file, then the phone locked —
    /// leaves the clock and the Live Activity where they are. Only a clock that has
    /// already reached the span end dismisses the activity from here.
    private func chainForward(from time: Date) {
        guard playing, !engineFailed, !rebuilding, holdUntil == nil else { return }
        if !skipsAudio, player.isPlaying, segment(at: time) != nil {
            return
        }
        guard let next = upcomingSegment(after: time) else {
            guard let end = activeSpan?.end, time >= end else { return }
            if displayClockPaused || lifetime.displayLink?.isPaused == true {
                pause(user: false)
                utc = end
                ended = true
                FlybyLiveActivity.scheduleEndAllImmediately()
                refreshNowPlaying(force: true)
            }
            return
        }
        let delay = next.start.timeIntervalSince(time)
        if delay <= 0.05 {
            utc = max(time, next.start)
            loadSegment(next)
        } else if displayClockPaused || lifetime.displayLink?.isPaused == true {
            scheduleAtRealStart(next, delay: delay)
        }
    }

    /// The next real file on this track that starts at or after `time`, inside the span.
    /// A file already playing is not selected again.
    private func upcomingSegment(after time: Date) -> Segment? {
        guard let timeline, let span = activeSpan else { return nil }
        return timeline.segments
            .filter { segment in
                segment.track == trackID
                    && segment.start >= span.start
                    && segment.start < span.end
                    && segment.start >= time - 0.05
            }
            .min { $0.start < $1.start }
    }

    /// Schedules the real file to begin after `delay` seconds of silence.
    /// The silence is the gap in the archive, not a generated bed.
    private func scheduleAtRealStart(_ segment: Segment, delay: TimeInterval) {
        guard delay > 0.05 else {
            loadSegment(segment)
            return
        }
        guard !unavailableFiles.contains(segment.file) else { return }
        guard let url = MediaStore.url(for: segment.file) else {
            unavailableFiles.insert(segment.file)
            return
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            unavailableFiles.insert(segment.file)
            return
        }
        audioFile = file
        currentFile = segment.file
        if !graphReady || usingEnvironment != spatial {
            let restart = engine.isRunning
            if restart {
                engine.stop()
            }
            connectGraph(format: file.processingFormat)
            if restart {
                do {
                    try startEngine()
                } catch {
                    failEngine()
                    return
                }
            }
        }
        reschedule(file: file, at: 0, when: hostTime(after: delay), lead: delay)
        holdUntil = segment.start
        do {
            if !engine.isRunning {
                try startEngine()
            }
            if playing {
                player.play()
            }
        } catch {
            failEngine()
        }
    }

    private func hostTime(after delay: TimeInterval) -> AVAudioTime {
        let now = mach_absolute_time()
        let seconds = AVAudioTime.seconds(forHostTime: now) + delay
        return AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: seconds))
    }

    /// Sample time includes a future schedule's silent wait. That wait is removed
    /// before the clock uses the value, and the result is never negative.
    private func renderedSeconds() -> TimeInterval {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.isSampleTimeValid,
              playerTime.sampleRate > 0 else {
            return max(0, holdSeconds)
        }
        let playerSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        let renderHost = nodeTime.isHostTimeValid ? AVAudioTime.seconds(forHostTime: nodeTime.hostTime) : nil
        return PlaybackTiming.fileSeconds(
            scheduledStart: scheduledStart,
            playerSeconds: playerSeconds,
            lead: scheduledLead,
            renderHostSeconds: renderHost,
            audibleHostSeconds: audibleHostSeconds
        )
    }

    private func segmentForCurrentFile() -> Segment? {
        guard let currentFile else { return nil }
        return timeline?.segments.first { $0.file == currentFile && $0.track == trackID }
    }

    // MARK: - Clock

    private func startDisplayLink() {
        guard lifetime.displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        lifetime.displayLink = link
    }

    @objc nonisolated private func tick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        MainActor.assumeIsolated {
            self.tickOnMain(timestamp)
        }
    }

    private func tickOnMain(_ timestamp: CFTimeInterval) {
        guard !rebuilding, !scrubbing else { return }
        let now = timestamp
        let rawDelta = lastWall.map { max(0, now - $0) } ?? 0
        lastWall = now

        if playing {
            if !skipsAudio, player.isPlaying, let segment = segmentForCurrentFile() {
                let seconds = renderedSeconds()
                if let armed = holdUntil, seconds <= 0, utc < armed {
                    utc = min(utc.addingTimeInterval(rawDelta), armed)
                } else {
                    if seconds > 0 {
                        holdUntil = nil
                    }
                    utc = segment.start.addingTimeInterval(seconds)
                    if utc >= segment.end {
                        utc = segment.end
                        holdSeconds = utc.timeIntervalSince(segment.start)
                        player.pause()
                    }
                }
            } else if let armed = holdUntil, utc < armed {
                utc = min(utc.addingTimeInterval(rawDelta), armed)
            } else {
                // The display link was paused in the background. This step is that
                // real silence, and it is not added on top of a file that is already playing.
                utc = utc.addingTimeInterval(rawDelta)
            }
            if let end = activeSpan?.end, utc >= end {
                utc = end
                pause(user: true)
                utc = end
                ended = true
                FlybyLiveActivity.scheduleEndAllImmediately()
            } else {
                followSegment()
            }
        }
        if usingEnvironment {
            easePan()
        }
        refreshNowPlaying(force: false)
    }

    // MARK: - Session

    private func activateSpokenSession() throws {
        guard RuntimeHost.allowsPlaybackServices() else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        try session.setActive(true)
    }

    /// Starting the engine activates the shared audio session. Tests that have not opted in never reach that.
    private func startEngine() throws {
        guard RuntimeHost.allowsPlaybackServices() else { return }
        if !engine.isRunning {
            try engine.start()
        }
    }

    // The session posts these on an arbitrary queue. The selectors stay
    // nonisolated and hop to the main actor before touching the player.
    private func observeNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    private func observeEngineConfiguration() {
        if let existing = lifetime.engineObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        lifetime.engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverEngineConfiguration()
            }
        }
    }

    /// The engine dropped its connections. If the node is still rendering, resume
    /// from that sample. Mission time can be stale while the phone is locked.
    private func recoverEngineConfiguration() {
        guard !rebuilding else { return }
        let wasPlaying = playing
        let armed = holdUntil
        let segment = segmentForCurrentFile()
        // The display link is paused while locked, so utc can sit at the last
        // file boundary. The node still knows the sample if it is rendering.
        let liveRender: TimeInterval? = (player.isPlaying && player.lastRenderTime != nil) ? renderedSeconds() : nil
        // Host time, read before stopPlayer() clears the anchor. `armed - utc` is
        // too long while the display link is paused.
        let measuredWait = audibleHostSeconds.map {
            PlaybackTiming.remainingWait(
                nowHostSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()),
                audibleHostSeconds: $0
            )
        }
        rebuilding = true
        defer { rebuilding = false }
        stopPlayer()
        graphReady = false
        usingEnvironment = false
        guard let file = audioFile else { return }
        let missionSeconds = segment.map { utc.timeIntervalSince($0.start) } ?? 0
        let rate = file.processingFormat.sampleRate
        let duration = rate > 0 ? Double(file.length) / rate : 0
        let secondsUntilArm = PlaybackTiming.gapDelay(
            remainingWait: measuredWait,
            armedOffset: armed.map { $0.timeIntervalSince(utc) }
        )
        switch PlaybackTiming.recoveryPlan(
            liveRenderSeconds: liveRender,
            secondsUntilArm: secondsUntilArm,
            missionSeconds: missionSeconds,
            fileDuration: duration
        ) {
        case .rearmGap(let delay):
            if let segment {
                scheduleAtRealStart(segment, delay: delay)
            }
            return
        case .resumeFile(let position, let clearHoldUntil):
            if clearHoldUntil {
                holdUntil = nil
            }
            if let segment {
                utc = min(segment.end, max(segment.start, segment.start.addingTimeInterval(position)))
            }
            connectGraph(format: file.processingFormat)
            reschedule(file: file, at: position)
            do {
                try startEngine()
                if wasPlaying {
                    player.play()
                }
            } catch {
                failEngine()
            }
        }
    }

    @objc nonisolated private func handleRouteChange(_ note: Notification) {
        let reason: AVAudioSession.RouteChangeReason? = Self.reason(note, key: AVAudioSessionRouteChangeReasonKey)
        guard let reason, reason == .oldDeviceUnavailable else { return }
        Task { @MainActor in
            self.pause(user: true)
        }
    }

    @objc nonisolated private func handleInterruption(_ note: Notification) {
        let type: AVAudioSession.InterruptionType? = Self.reason(note, key: AVAudioSessionInterruptionTypeKey)
        let optionsNumber = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsNumber?.uintValue ?? 0)
        guard let type else { return }
        Task { @MainActor in
            switch type {
            case .began:
                self.resumeAfterInterrupt = self.playing
                self.pause(user: false)
            case .ended:
                if options.contains(.shouldResume), self.resumeAfterInterrupt {
                    self.play(fromHold: true)
                }
                self.resumeAfterInterrupt = false
            @unknown default:
                break
            }
        }
    }

    @objc nonisolated private func handleMediaReset(_ note: Notification) {
        Task { @MainActor in
            self.rebuildEngine()
        }
    }

    private func rebuildEngine() {
        guard !skipsAudio else { return }
        rebuilding = true
        defer { rebuilding = false }
        stopPlayer()
        engine.stop()
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        environment = AVAudioEnvironmentNode()
        audioFile = nil
        currentFile = nil
        holdUntil = nil
        graphReady = false
        usingEnvironment = false
        attachGraph()
        configureEnvironment()
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        observeEngineConfiguration()
        if arrived {
            do {
                try activateSpokenSession()
            } catch {
                failEngine()
            }
        }
        if playing {
            followSegment()
        }
    }

    nonisolated private static func reason<T: RawRepresentable>(_ note: Notification, key: String) -> T? where T.RawValue == UInt {
        guard let number = note.userInfo?[key] as? NSNumber else { return nil }
        return T(rawValue: number.uintValue)
    }

    // MARK: - Now Playing

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]

        add(center.playCommand) { model, _ in
            model.play()
        }
        add(center.pauseCommand) { model, _ in
            model.pause(user: true)
        }
        add(center.togglePlayPauseCommand) { model, _ in
            model.toggle()
        }
        add(center.skipForwardCommand, read: .skipForward) { model, interval in
            model.skip(by: interval)
        }
        add(center.skipBackwardCommand, read: .skipBackward) { model, interval in
            model.skip(by: interval)
        }
        add(center.changePlaybackPositionCommand, read: .position) { model, position in
            model.seekElapsed(position)
        }
    }

    private enum RemoteRead: Sendable {
        case unused
        case skipForward
        case skipBackward
        case position
    }

    /// `MPRemoteCommandEvent` is not Sendable. The handler copies `interval`
    /// and `positionTime` into locals, then hops only that number.
    private func add(
        _ command: MPRemoteCommand,
        read: RemoteRead = .unused,
        action: @escaping @MainActor (PlaybackModel, Double) -> Void
    ) {
        // The addTarget handler must stay @Sendable. The unit test covers
        // deliver, not this closure.
        let token = command.addTarget { @Sendable [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipInterval
            let positionTime = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            let number: Double?
            switch read {
            case .unused:
                number = 0
            case .skipForward:
                number = interval
            case .skipBackward:
                number = -interval
            case .position:
                number = positionTime
            }
            guard let number else { return .commandFailed }
            Self.deliver(number) { [weak self] value in
                guard let self else { return }
                action(self, value)
            }
            return .success
        }
        lifetime.commands.append((command, token))
    }

    /// Hop a remote-command number onto the main actor. A handler that is
    /// already on the main thread runs immediately; any other queue asyncs.
    nonisolated static func deliver(
        _ value: Double,
        action: @escaping @MainActor (Double) -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { action(value) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { action(value) }
            }
        }
    }

    private func refreshNowPlaying(force: Bool) {
        guard !skipsAudio || postsLiveActivityWhileSkippingAudio else { return }
        guard arrived, let span = activeSpan else { return }
        let elapsed = max(0, utc.timeIntervalSince(span.start))
        let second = Int(elapsed.rounded(.down))
        let artID = artworkID()
        // A dismissal can remove the activity without moving the clock. Notice it once,
        // then let the 15s cadence retry, so a failed request does not push every frame.
        let activityMissing = playing && !FlybyLiveActivity.isRunning
        let becameMissing = activityMissing && !lastActivityWasMissing
        if !force, second == lastInfoSecond, playing == lastInfoPlaying, artID == lastArtID, !becameMissing {
            return
        }
        lastInfoSecond = second
        lastInfoPlaying = playing
        lastArtID = artID
        lastActivityWasMissing = activityMissing
        if !skipsAudio {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: span.label,
                MPMediaItemPropertyArtist: "NASA/Artemis II Crew",
                MPMediaItemPropertyAlbumTitle: "Artemis II",
                MPMediaItemPropertyPlaybackDuration: span.end.timeIntervalSince(span.start),
                MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
                MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            ]
            if let image = artworkImage() {
                info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        let duration = span.end.timeIntervalSince(span.start)
        let milestones = timeline.map { MilestoneList.derive($0) } ?? []
        let speaker = LyricFocus.focus(at: utc, track: trackID, lines: timeline?.lines ?? []).current?.speaker ?? crewID
        let spanEnded = utc >= span.end
        let requested = activityEvent
        activityEvent = false
        let playbackChanged = lastActivityPlaying != playing
        let speakerChanged = speaker != lastActivitySpeaker
        let endedChanged = spanEnded != lastActivityEnded
        let due = playing && Date().timeIntervalSince(lastActivityPush) >= Self.activityPushInterval
        // Background, pause, seek, and span end pass force and are not held for the 15s cadence.
        guard force || requested || becameMissing || playbackChanged || speakerChanged || endedChanged || due else { return }
        lastActivityPush = Date()
        lastActivitySpeaker = speaker
        lastActivityPlaying = playing
        lastActivityEnded = spanEnded
        let rate = playing ? 1.0 : 0.0
        FlybyLiveActivity.sync(
            arrived: arrived,
            playing: playing,
            progress: FlybyActivityCopy.progress(elapsed: elapsed, duration: duration),
            nextMilestone: FlybyActivityCopy.nextLabel(after: utc, milestones: milestones),
            speaker: speaker,
            clock: FlybyActivityCopy.lockScreenClock(utc),
            staleDate: FlybyActivityCopy.staleDate(playing: playing, utc: utc, spanEnd: span.end, rate: rate)
        )
    }

    /// MediaPlayer calls the handler on its access queue. The image is already
    /// resolved, and this handler only reads it.
    nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private func artworkID() -> String {
        pair(for: window).current?.nasaID ?? ""
    }

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
        let cap = maxPixel > 1 ? maxPixel : ScreenImage.maxPixel
        return MediaStore.cachedImage(file: frame.file, small: phoneImages, maxPixel: cap)
    }

    func prefetch(_ frame: Frame, maxPixel: CGFloat) {
        let cap = maxPixel > 1 ? maxPixel : ScreenImage.maxPixel
        MediaStore.prefetch(file: frame.file, small: phoneImages, maxPixel: cap) { [weak self] in
            self?.noteFramesDecoded(file: frame.file)
        }
    }

    private func artworkImage() -> UIImage? {
        let file = currentArtworkFile()
        if let image = MediaStore.cachedImage(file: file, small: true, maxPixel: 720) {
            return image
        }
        MediaStore.prefetch(file: file, small: true, maxPixel: 720) { [weak self] in
            self?.noteFramesDecoded(file: file)
        }
        return nil
    }
}

/// Decode cap for a full-bleed frame. The file on disk is larger than the glass.
enum ScreenImage {
    static func maxPixel(bounds: CGSize, scale: CGFloat) -> CGFloat {
        let edge = max(bounds.width, bounds.height) * max(scale, 1)
        guard edge.isFinite, edge >= 200 else { return 1600 }
        return min(3000, ceil(edge))
    }

    static var maxPixel: CGFloat {
        maxPixel(bounds: UIScreen.main.bounds, scale: UIScreen.main.scale)
    }
}

@MainActor
enum MediaStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private static var inflight = Set<String>()
    private static var failed = Set<String>()
    private static var attempts: [String: Int] = [:]
    private static var waiters: [String: @MainActor () -> Void] = [:]
    private static var pinned: [String: UIImage] = [:]
    private static var pinOrder: [String] = []
    private static var memoryObserver: NSObjectProtocol?

    static func observeMemoryWarning() {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { @Sendable _ in
            MainActor.assumeIsolated {
                MediaStore.allowRetries()
            }
        }
    }

    static func allowRetries() {
        failed.removeAll()
        attempts.removeAll()
        while pinOrder.count > 2 {
            let oldest = pinOrder.removeFirst()
            pinned.removeValue(forKey: oldest)
        }
    }

    nonisolated static func pixelBucket(_ maxPixel: CGFloat) -> Int {
        max(32, Int((max(maxPixel, 1) / 32).rounded(.up)) * 32)
    }

    static func demoRoot() -> URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("DemoData") else { return nil }
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    /// Only paths inside DemoData. `..` and absolute components are refused.
    static func url(for relative: String) -> URL? {
        guard DemoPath.isContained(relative), let root = demoRoot() else { return nil }
        let url = root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func variant(_ file: String, small: Bool) -> String {
        guard small, file.hasSuffix(".webp"), !file.hasSuffix(".720.webp") else { return file }
        let sibling = file.replacingOccurrences(of: ".webp", with: ".720.webp")
        return url(for: sibling) != nil ? sibling : file
    }

    /// Cache read. A few on-screen frames are also held strongly, so an eviction
    /// does not turn the glass black.
    static func cachedImage(file: String, small: Bool, maxPixel: CGFloat) -> UIImage? {
        let key = cacheKey(file: file, small: small, maxPixel: maxPixel)
        let name = key as String
        if let cached = cache.object(forKey: key) {
            pin(name, cached)
            return cached
        }
        return pinned[name]
    }

    /// Decodes off the main thread and stores the image on the main actor.
    static func prefetch(file: String, small: Bool, maxPixel: CGFloat, ready: @escaping @MainActor () -> Void) {
        let key = cacheKey(file: file, small: small, maxPixel: maxPixel)
        let name = key as String
        if cache.object(forKey: key) != nil || pinned[name] != nil || failed.contains(name) {
            return
        }
        if inflight.contains(name) {
            let previous = waiters[name]
            waiters[name] = {
                previous?()
                ready()
            }
            return
        }
        guard let url = url(for: variant(file, small: small)) else {
            failed.insert(name)
            return
        }
        guard RuntimeHost.mayDecodeImages else { return }
        inflight.insert(name)
        waiters[name] = ready
        let pixels = CGFloat(pixelBucket(maxPixel))
        Task.detached(priority: .userInitiated) {
            let owned = ImageDecode.thumbnail(url: url, maxPixel: pixels)
            await MainActor.run {
                MediaStore.finishPrefetch(name: name, owned: owned, url: url, maxPixel: pixels)
            }
        }
    }

    private static func cacheKey(file: String, small: Bool, maxPixel: CGFloat) -> NSString {
        let name = variant(file, small: small)
        return "\(name)@\(pixelBucket(maxPixel))" as NSString
    }

    private static func finishPrefetch(name: String, owned: ImageDecode.Owned?, url: URL, maxPixel: CGFloat) {
        inflight.remove(name)
        let ready = waiters.removeValue(forKey: name)
        let image = owned.map { UIImage(cgImage: $0.cgImage) } ?? fallbackImage(url: url, maxPixel: maxPixel)
        guard let image else {
            let count = (attempts[name] ?? 0) + 1
            attempts[name] = count
            if count >= 2 {
                failed.insert(name)
            }
            // Wake the view so it can keep the previous frame up and try once more.
            ready?()
            return
        }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: name as NSString, cost: cost)
        pin(name, image)
        ready?()
    }

    private static func pin(_ name: String, _ image: UIImage) {
        pinOrder.removeAll { $0 == name }
        pinOrder.append(name)
        pinned[name] = image
        while pinOrder.count > 4 {
            let oldest = pinOrder.removeFirst()
            pinned.removeValue(forKey: oldest)
        }
    }

    /// Used only when ImageIO cannot read the file. The view never calls this.
    private static func fallbackImage(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let full = UIImage(contentsOfFile: url.path) else { return nil }
        let longest = max(full.size.width, full.size.height) * full.scale
        let ratio = min(1, maxPixel / max(longest, 1))
        guard ratio < 0.99 else { return full }
        let target = CGSize(width: full.size.width * ratio, height: full.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            full.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
