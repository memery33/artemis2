import AVFoundation
import Combine
import ImageIO
import MediaPlayer
import UIKit

enum MissionRange: Equatable {
    case flyby
    case cab
}

/// Tokens owned for the life of the player. Deinit is not main-actor isolated,
/// so remote-command targets and the engine observer live here.
private final class PlaybackLifetime: @unchecked Sendable {
    var engineObserver: NSObjectProtocol?
    var displayLink: CADisplayLink?
    var commands: [(MPRemoteCommand, Any)] = []

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
    @Published var engineFailed = false
    /// Phone layout reads the 720 sibling. The open fold reads the shipped frame.
    @Published var phoneImages = true

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var environment = AVAudioEnvironmentNode()
    private var audioFile: AVAudioFile?
    private var currentFile: String?
    private var scheduledStart: TimeInterval = 0
    private var holdSeconds: TimeInterval = 0
    /// Mission time when a file scheduled in the future should become audible.
    private var holdUntil: Date?
    private var scheduleGeneration = 0
    private var usingEnvironment = false
    private var graphReady = false
    private var pan: Float = 0
    private var rebuilding = false
    private var resumeAfterInterrupt = false
    private var commandsInstalled = false
    private var lastWall: CFTimeInterval?
    private var lastInfoSecond = Int.min
    private var lastInfoPlaying = false
    private var lastArtID = ""
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var unavailableFiles = Set<String>()
    nonisolated private let lifetime = PlaybackLifetime()

    override init() {
        super.init()
        spatial = UserDefaults.standard.bool(forKey: Self.spatialDefaultsKey)
        loadTimeline()
        attachGraph()
        configureEnvironment()
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        observeNotifications()
        observeEngineConfiguration()
    }

    deinit {
        lifetime.tearDown()
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
        guard !engineFailed else {
            refreshNowPlaying(force: true)
            return
        }
        if let armed = holdUntil, armed > utc, let segment = segmentForCurrentFile() {
            scheduleAtRealStart(segment, delay: armed.timeIntervalSince(utc))
            refreshNowPlaying(force: true)
            return
        }
        if fromHold, let file = audioFile, currentFile != nil {
            reschedule(file: file, at: max(0, holdSeconds))
        }
        do {
            try activateSpokenSession()
            if !engine.isRunning {
                try engine.start()
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
        if player.isPlaying {
            holdSeconds = renderedSeconds()
        }
        player.pause()
        playing = false
        if user {
            resumeAfterInterrupt = false
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

    func seek(to date: Date) {
        guard let span = activeSpan else { return }
        var target = date
        if target < span.start { target = span.start }
        if target > span.end { target = span.end }
        utc = target
        holdUntil = nil
        rebuilding = true
        defer { rebuilding = false }
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
            scheduleGeneration += 1
            holdSeconds = 0
            player.stop()
        }
        refreshNowPlaying(force: true)
    }

    private func restartPlayerIfNeeded() {
        guard playing, !engineFailed, audioFile != nil else { return }
        do {
            if !engine.isRunning {
                try engine.start()
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
        guard playing, !engineFailed else { return }
        do {
            if !engine.isRunning {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
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
        let wasPlaying = playing && player.isPlaying
        rebuilding = true
        defer { rebuilding = false }
        scheduleGeneration += 1
        player.stop()
        engine.stop()
        graphReady = false
        usingEnvironment = false
        connectGraph(format: file.processingFormat)
        reschedule(file: file, at: seconds)
        do {
            try engine.start()
            if wasPlaying { player.play() }
        } catch {
            failEngine()
        }
    }

    func setSceneActive(_ active: Bool) {
        if active {
            lifetime.displayLink?.isPaused = false
            if holdUntil == nil, player.isPlaying, let segment = segmentForCurrentFile() {
                utc = segment.start.addingTimeInterval(renderedSeconds())
                lastWall = nil
            }
        } else {
            lifetime.displayLink?.isPaused = true
            if playing {
                chainForward(from: utc)
            }
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
        player.stop()
        refreshNowPlaying(force: true)
    }

    private func reloadAtCurrentTime() {
        currentFile = nil
        audioFile = nil
        holdUntil = nil
        scheduleGeneration += 1
        player.stop()
        if playing { followSegment() }
        refreshNowPlaying(force: true)
    }

    private func followSegment() {
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
        if unavailableFiles.contains(segment.file) {
            currentFile = segment.file
            audioFile = nil
            player.stop()
            return
        }
        guard let url = MediaStore.url(for: segment.file) else {
            unavailableFiles.insert(segment.file)
            currentFile = segment.file
            audioFile = nil
            player.stop()
            return
        }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            unavailableFiles.insert(segment.file)
            currentFile = segment.file
            audioFile = nil
            player.stop()
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
                    try engine.start()
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
                try engine.start()
            }
            player.play()
        } catch {
            failEngine()
        }
    }

    private func reschedule(file: AVAudioFile, at seconds: TimeInterval, when: AVAudioTime? = nil) {
        scheduleGeneration += 1
        let generation = scheduleGeneration
        player.stop()
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
        player.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: count,
            at: when,
            completionHandler: { [weak self] in
                let endSeconds = actual + Double(count) / rate
                Task { @MainActor in
                    guard let model = self, model.scheduleGeneration == generation else { return }
                    model.holdSeconds = endSeconds
                    model.segmentDidFinish()
                }
            }
        )
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
            pause(user: true)
            return
        }
        chainForward(from: utc)
    }

    /// Plays the next real segment, or arms it at its own start time.
    /// A span with nothing left to play pauses and sets the Now Playing rate to 0.
    private func chainForward(from time: Date) {
        guard playing, !engineFailed, !rebuilding, holdUntil == nil else { return }
        if player.isPlaying, segment(at: time) != nil {
            return
        }
        guard let next = upcomingSegment(after: time) else {
            if lifetime.displayLink?.isPaused == true {
                pause(user: false)
            }
            return
        }
        let delay = next.start.timeIntervalSince(time)
        if delay <= 0.05 {
            utc = max(time, next.start)
            loadSegment(next)
        } else if lifetime.displayLink?.isPaused == true {
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
                    try engine.start()
                } catch {
                    failEngine()
                    return
                }
            }
        }
        reschedule(file: file, at: 0, when: hostTime(after: delay))
        holdUntil = segment.start
        do {
            if !engine.isRunning {
                try engine.start()
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

    /// Sample time is relative to the scheduled segment, which itself starts
    /// at `scheduledStart` seconds into the file.
    private func renderedSeconds() -> TimeInterval {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = player.playerTime(forNodeTime: nodeTime),
              playerTime.isSampleTimeValid,
              playerTime.sampleRate > 0 else {
            return holdSeconds
        }
        return scheduledStart + Double(playerTime.sampleTime) / playerTime.sampleRate
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
        MainActor.assumeIsolated {
            self.tickOnMain(link)
        }
    }

    private func tickOnMain(_ link: CADisplayLink) {
        guard !rebuilding else { return }
        let now = link.timestamp
        let rawDelta = lastWall.map { max(0, now - $0) } ?? 0
        lastWall = now

        if playing {
            if let armed = holdUntil, utc < armed {
                utc = utc.addingTimeInterval(rawDelta)
                if utc >= armed {
                    holdUntil = nil
                }
            } else if player.isPlaying, let segment = segmentForCurrentFile() {
                utc = segment.start.addingTimeInterval(renderedSeconds())
                if utc >= segment.end {
                    utc = segment.end
                    holdSeconds = utc.timeIntervalSince(segment.start)
                    player.pause()
                }
            } else {
                // A large step here is real time spent in a silent gap,
                // including time the display link was paused in the background.
                utc = utc.addingTimeInterval(rawDelta)
            }
            if let end = activeSpan?.end, utc >= end {
                utc = end
                pause(user: true)
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
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        try session.setActive(true)
    }

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
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverEngineConfiguration()
            }
        }
    }

    /// The engine dropped its connections. Put the same file back at the same sample.
    private func recoverEngineConfiguration() {
        guard !rebuilding else { return }
        let seconds = renderedSeconds()
        let wasPlaying = playing && (player.isPlaying || holdUntil != nil)
        let armed = holdUntil
        let armedSegment = segmentForCurrentFile()
        rebuilding = true
        defer { rebuilding = false }
        scheduleGeneration += 1
        player.stop()
        graphReady = false
        usingEnvironment = false
        if let armed, armed > utc, let armedSegment {
            scheduleAtRealStart(armedSegment, delay: max(0, armed.timeIntervalSince(utc)))
            if !wasPlaying {
                player.pause()
            }
            return
        }
        guard let file = audioFile else { return }
        connectGraph(format: file.processingFormat)
        reschedule(file: file, at: seconds)
        do {
            try engine.start()
            if wasPlaying {
                player.play()
            }
        } catch {
            failEngine()
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
        rebuilding = true
        defer { rebuilding = false }
        engine.stop()
        player.stop()
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
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]

        add(center.playCommand) { model, _ in
            model.play()
        }
        add(center.pauseCommand) { model, _ in
            model.pause(user: true)
        }
        add(center.togglePlayPauseCommand) { model, _ in
            model.toggle()
        }
        add(center.skipForwardCommand) { model, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            model.skip(by: interval)
        }
        add(center.skipBackwardCommand) { model, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            model.skip(by: -interval)
        }
        let positionCommand = center.changePlaybackPositionCommand
        let positionToken = positionCommand.addTarget { event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.seekElapsed(position)
            }
            return .success
        }
        lifetime.commands.append((positionCommand, positionToken))
    }

    private func add(
        _ command: MPRemoteCommand,
        action: @escaping @MainActor (PlaybackModel, MPRemoteCommandEvent) -> Void
    ) {
        let token = command.addTarget { event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self, event)
            }
            return .success
        }
        lifetime.commands.append((command, token))
    }

    private func refreshNowPlaying(force: Bool) {
        guard arrived, let span = activeSpan else { return }
        let elapsed = max(0, utc.timeIntervalSince(span.start))
        let second = Int(elapsed.rounded(.down))
        let artID = artworkID()
        if !force, second == lastInfoSecond, playing == lastInfoPlaying, artID == lastArtID {
            return
        }
        lastInfoSecond = second
        lastInfoPlaying = playing
        lastArtID = artID
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: span.label,
            MPMediaItemPropertyArtist: "NASA/Artemis II Crew",
            MPMediaItemPropertyAlbumTitle: "Artemis II",
            MPMediaItemPropertyPlaybackDuration: span.end.timeIntervalSince(span.start),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if let image = artworkImage() {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artworkID() -> String {
        guard let frames = timeline?.frames else { return "" }
        return FrameSelection.visiblePair(at: utc, window: window, frames: frames).current?.nasaID ?? ""
    }

    private func artworkImage() -> UIImage? {
        if let frames = timeline?.frames,
           let frame = FrameSelection.visiblePair(at: utc, window: window, frames: frames).current,
           let image = MediaStore.image(file: frame.file, small: true, maxPixel: 720) {
            return image
        }
        return MediaStore.image(file: "images/art002e016184.webp", small: true, maxPixel: 720)
    }
}

@MainActor
enum MediaStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func demoRoot() -> URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("DemoData") else { return nil }
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    static func url(for relative: String) -> URL? {
        guard let root = demoRoot() else { return nil }
        let url = root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func variant(_ file: String, small: Bool) -> String {
        guard small, file.hasSuffix(".webp"), !file.hasSuffix(".720.webp") else { return file }
        let sibling = file.replacingOccurrences(of: ".webp", with: ".720.webp")
        return url(for: sibling) != nil ? sibling : file
    }

    static func image(file: String, small: Bool, maxPixel: CGFloat) -> UIImage? {
        let name = variant(file, small: small)
        let bucket = max(32, Int((max(maxPixel, 1) / 32).rounded(.up)) * 32)
        let key = "\(name)@\(bucket)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = url(for: name), let image = downsample(url: url, maxPixel: CGFloat(bucket)) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            ] as CFDictionary
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                return UIImage(cgImage: cgImage)
            }
        }
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
