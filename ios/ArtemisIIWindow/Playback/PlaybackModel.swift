import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum MissionRange: Equatable {
    case flyby
    case cab
}

/// One master clock. The crew recording is the time source while a real file
/// is playing. Gaps, including the opening seconds before the first file,
/// advance on the wall clock and stay silent. Nothing is synthesized.
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
    private var scheduleGeneration = 0
    private var usingEnvironment = false
    private var graphReady = false
    private var pan: Float = 0
    private var rebuilding = false
    private var resumeAfterInterrupt = false
    private var commandsInstalled = false
    private var displayLink: CADisplayLink?
    private var lastWall: CFTimeInterval?
    private var lastInfoSecond = Int.min
    private var lastInfoPlaying = false
    private var lastArtID = ""
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var unavailableFiles = Set<String>()

    override init() {
        super.init()
        spatial = UserDefaults.standard.bool(forKey: Self.spatialDefaultsKey)
        loadTimeline()
        attachGraph()
        configureEnvironment()
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        observeNotifications()
    }

    deinit {
        displayLink?.invalidate()
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
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
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

    func play() {
        guard timeline != nil else { return }
        if let end = activeSpan?.end, utc >= end, let start = activeSpan?.start {
            utc = start
            currentFile = nil
        }
        playing = true
        resumeAfterInterrupt = false
        guard !engineFailed else {
            refreshNowPlaying(force: true)
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
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
        setWindow(.cab)
        reloadAtCurrentTime()
    }

    func showFlyby() {
        range = .flyby
        utc = timeline?.window.start ?? utc
        setWindow(.nikon)
        reloadAtCurrentTime()
    }

    func seek(to date: Date) {
        guard let span = activeSpan else { return }
        var target = date
        if target < span.start { target = span.start }
        if target > span.end { target = span.end }
        utc = target
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
        seek(to: line.date)
        if playing, !engineFailed {
            if !engine.isRunning {
                try? engine.start()
            }
            if let segment = segment(at: utc), currentFile == segment.file, audioFile != nil, !player.isPlaying {
                player.play()
            }
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
            displayLink?.isPaused = false
            if player.isPlaying, let segment = segmentForCurrentFile() {
                utc = segment.start.addingTimeInterval(renderedSeconds())
                lastWall = nil
            }
        } else {
            displayLink?.isPaused = true
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
        player.renderingAlgorithm = .equalPower
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
        engineFailed = true
        player.stop()
        refreshNowPlaying(force: true)
    }

    private func reloadAtCurrentTime() {
        currentFile = nil
        audioFile = nil
        scheduleGeneration += 1
        player.stop()
        if playing { followSegment() }
        refreshNowPlaying(force: true)
    }

    private func followSegment() {
        guard playing, !engineFailed else { return }
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

    private func reschedule(file: AVAudioFile, at seconds: TimeInterval) {
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
            at: nil,
            completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    guard let model = self, model.scheduleGeneration == generation else { return }
                    model.holdSeconds = actual + Double(count) / rate
                }
            }
        )
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
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !rebuilding else { return }
        let now = link.timestamp
        let rawDelta = lastWall.map { max(0, now - $0) } ?? 0
        lastWall = now

        if playing {
            if player.isPlaying, let segment = segmentForCurrentFile() {
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

    @objc private func handleRouteChange(_ note: Notification) {
        let reason: AVAudioSession.RouteChangeReason? = Self.rawValue(note, key: AVAudioSessionRouteChangeReasonKey)
        guard let reason = reason, reason == .oldDeviceUnavailable else { return }
        DispatchQueue.main.async { [weak self] in
            self?.pause(user: true)
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        let type: AVAudioSession.InterruptionType? = Self.rawValue(note, key: AVAudioSessionInterruptionTypeKey)
        let optionsNumber = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsNumber?.uintValue ?? 0)
        guard let type = type else { return }
        DispatchQueue.main.async { [weak self] in
            guard let model = self else { return }
            switch type {
            case .began:
                model.resumeAfterInterrupt = model.playing
                model.pause(user: false)
            case .ended:
                if options.contains(.shouldResume), model.resumeAfterInterrupt {
                    model.play()
                }
                model.resumeAfterInterrupt = false
            @unknown default:
                break
            }
        }
    }

    @objc private func handleMediaReset(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.rebuildEngine()
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
        graphReady = false
        usingEnvironment = false
        attachGraph()
        configureEnvironment()
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        if arrived {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        if playing {
            followSegment()
        }
    }

    private static func rawValue<T: RawRepresentable>(_ note: Notification, key: String) -> T? where T.RawValue == UInt {
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

        center.playCommand.addTarget { [weak self] _ in
            self?.performOnMain { $0.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.performOnMain { $0.pause(user: true) }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.performOnMain { $0.toggle() }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self?.performOnMain { $0.skip(by: interval) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            self?.performOnMain { $0.skip(by: -interval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            self?.performOnMain { $0.seekElapsed(position) }
            return .success
        }
    }

    private func performOnMain(_ work: @escaping (PlaybackModel) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let model = self else { return }
                work(model)
            }
        }
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
           let image = MediaStore.image(file: frame.file, small: false) {
            return image
        }
        return MediaStore.image(file: "images/art002e016184.webp", small: false)
    }
}

enum MediaStore {
    static var images: [String: UIImage] = [:]

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

    static func image(file: String, small: Bool) -> UIImage? {
        let name = variant(file, small: small)
        if let cached = images[name] { return cached }
        guard let url = url(for: name), let image = UIImage(contentsOfFile: url.path) else { return nil }
        images[name] = image
        return image
    }
}
