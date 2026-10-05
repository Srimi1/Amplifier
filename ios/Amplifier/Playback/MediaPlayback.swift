import AVFoundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class MediaPlayback {
    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let systemControls: Bool
    @ObservationIgnored private var processor: AMPGainProcessor?
    @ObservationIgnored private var mediaURL: URL?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playerObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var commandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var resumeAfterInterruption = false

    var title = ""
    var hasVideo = false
    var hasAudio = false
    var isImporting = false
    var isReady = false
    var isPlaying = false
    var isBuffering = false
    var duration = 0.0
    var currentTime = 0.0
    var processedFrames: UInt64 = 0
    var unsupportedFormat = false
    var errorMessage: String?

    var gainDB: Double {
        didSet {
            processor?.gainDB = Float(gainDB)
            defaults.set(gainDB, forKey: "gainDB")
        }
    }
    var boostEnabled: Bool {
        didSet {
            processor?.isEnabled = boostEnabled
            defaults.set(boostEnabled, forKey: "boostEnabled")
        }
    }

    var hasMedia: Bool { mediaURL != nil }
    var canBoost: Bool { hasAudio && !unsupportedFormat }
    var status: String {
        if isImporting { return "Opening media…" }
        if !hasMedia { return "Choose a file to begin." }
        if !hasAudio { return "This video has no audio track." }
        if unsupportedFormat { return "This audio format can’t be boosted. Playback is unchanged." }
        if !boostEnabled || gainDB == 0 { return "Boost bypassed for this file." }
        if isPlaying && processedFrames > 0 { return "Boosting this file." }
        return "Boost ready for this file."
    }

    init(defaults: UserDefaults = .standard, systemControls: Bool = true) {
        self.defaults = defaults
        self.systemControls = systemControls
        let stored = defaults.object(forKey: "gainDB") == nil ? 6.0 : defaults.double(forKey: "gainDB")
        gainDB = stored.isFinite ? min(15, max(0, stored)) : 6.0
        boostEnabled = defaults.object(forKey: "boostEnabled") == nil ? true : defaults.bool(forKey: "boostEnabled")
        playerObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.synchronizePlayback() }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                self.currentTime = seconds.isFinite ? max(0, seconds) : 0
                self.processedFrames = self.processor?.processedFrames ?? 0
                self.unsupportedFormat = self.processor?.unsupportedFormatEncountered ?? false
            }
        }
        if systemControls { registerSystemControls() }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        for (command, target) in commandTargets { command.removeTarget(target) }
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let filename = defaults.string(forKey: "lastMediaName")
        await Task.detached(priority: .utility) { MediaFiles.cleanup(keeping: filename) }.value
        guard let filename, !filename.contains("/"), filename != ".", filename != ".." else { return }
        let url = MediaFiles.directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            defaults.removeObject(forKey: "lastMediaName")
            defaults.removeObject(forKey: "lastMediaTitle")
            return
        }
        do { try await prepare(url, title: defaults.string(forKey: "lastMediaTitle") ?? "Imported media") }
        catch is CancellationError { return }
        catch { errorMessage = "The saved file couldn’t be restored. Choose it again from Files." }
    }

    func importFile(_ source: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        _ = await performImport(source)
    }

    private func performImport(_ source: URL) async -> Bool {
        errorMessage = nil
        var copied: URL?
        do {
            let imported = try await Task.detached(priority: .userInitiated) { try MediaFiles.copy(source) }.value
            copied = imported.url
            try Task.checkCancellation()
            let old = mediaURL
            try await prepare(imported.url, title: imported.title)
            defaults.set(imported.url.lastPathComponent, forKey: "lastMediaName")
            defaults.set(imported.title, forKey: "lastMediaTitle")
            MediaFiles.remove(old)
            return true
        } catch is CancellationError {
            MediaFiles.remove(copied)
        } catch {
            MediaFiles.remove(copied)
            errorMessage = (error as? MediaError)?.errorDescription ?? MediaError.unreadable.errorDescription
        }
        return false
    }

    func loadSample() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let sample = try await Task.detached(priority: .userInitiated) { try DemoTone.make() }.value
            defer { try? FileManager.default.removeItem(at: sample) }
            if await performImport(sample) {
                title = "Amplifier sample"
                defaults.set(title, forKey: "lastMediaTitle")
                updateNowPlaying()
            }
        } catch { errorMessage = "The sample couldn’t be created. Try importing your own file." }
    }

    private func prepare(_ url: URL, title newTitle: String) async throws {
        let asset = AVURLAsset(url: url)
        async let playable = asset.load(.isPlayable)
        async let protected = asset.load(.hasProtectedContent)
        async let assetDuration = asset.load(.duration)
        async let audio = asset.loadTracks(withMediaType: .audio)
        async let video = asset.loadTracks(withMediaType: .video)
        let (canPlay, hasProtection, length, audioTracks, videoTracks) = try await (playable, protected, assetDuration, audio, video)
        try Task.checkCancellation()
        guard !hasProtection else { throw MediaError.protectedContent }
        guard canPlay else { throw MediaError.unplayable }
        guard !audioTracks.isEmpty || !videoTracks.isEmpty else { throw MediaError.noTracks }
        let nextProcessor = AMPGainProcessor()
        nextProcessor.gainDB = Float(gainDB)
        nextProcessor.isEnabled = boostEnabled
        let nextItem = AVPlayerItem(asset: asset)
        if !audioTracks.isEmpty {
            guard let mix = nextProcessor.audioMix(for: audioTracks) else { throw MediaError.processingUnavailable }
            nextItem.audioMix = mix
        }
        pause()
        itemObservation = nil
        processor = nextProcessor
        mediaURL = url
        title = newTitle
        hasVideo = !videoTracks.isEmpty
        hasAudio = !audioTracks.isEmpty
        duration = length.seconds.isFinite ? max(0, length.seconds) : 0
        currentTime = 0
        processedFrames = 0
        unsupportedFormat = false
        isReady = false
        player.replaceCurrentItem(with: nextItem)
        itemObservation = nextItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, item === self.player.currentItem else { return }
                self.isReady = item.status == .readyToPlay
                if item.status == .failed { self.errorMessage = MediaError.unplayable.errorDescription }
                self.updateNowPlaying()
            }
        }
        updateNowPlaying()
    }

    func play() {
        guard isReady else { return }
        do {
            if systemControls {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
            }
            errorMessage = nil
            if duration > 0 && currentTime >= duration - 0.05 {
                seek(to: 0, resume: true)
            } else {
                player.play()
            }
        } catch { errorMessage = "Audio playback couldn’t start. Try again after the call or other audio stops." }
    }

    func pause() {
        resumeAfterInterruption = false
        player.pause()
        if systemControls { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        synchronizePlayback()
    }

    func togglePlayback() { isPlaying ? pause() : play() }

    func seek(to seconds: Double, resume: Bool = false) {
        guard isReady, seconds.isFinite, let item = player.currentItem else { return }
        let value = min(duration, max(0, seconds))
        player.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            Task { @MainActor [weak self] in
                guard let self, completed, item === self.player.currentItem else { return }
                self.currentTime = value
                if resume { self.player.play() }
                self.updateNowPlaying()
            }
        }
    }

    func clear() {
        guard !isImporting else { return }
        pause()
        itemObservation = nil
        player.replaceCurrentItem(with: nil)
        processor = nil
        MediaFiles.remove(mediaURL)
        mediaURL = nil
        title = ""
        hasVideo = false
        hasAudio = false
        isReady = false
        duration = 0
        currentTime = 0
        processedFrames = 0
        unsupportedFormat = false
        defaults.removeObject(forKey: "lastMediaName")
        defaults.removeObject(forKey: "lastMediaTitle")
        updateNowPlaying()
    }

    private func synchronizePlayback() {
        isPlaying = player.timeControlStatus == .playing
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard systemControls else { return }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = isReady
        center.pauseCommand.isEnabled = isReady
        center.togglePlayPauseCommand.isEnabled = isReady
        center.changePlaybackPositionCommand.isEnabled = isReady && duration > 0
        guard hasMedia else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func registerSystemControls() {
        let commands = MPRemoteCommandCenter.shared()
        for (command, action) in [(commands.playCommand, 0), (commands.pauseCommand, 1), (commands.togglePlayPauseCommand, 2)] {
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch action { case 0: self.play(); case 1: self.pause(); default: self.togglePlayback() }
                }
                return .success
            }
            commandTargets.append((command, target))
        }
        let positionTarget = commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
        commandTargets.append((commands.changePlaybackPositionCommand, positionTarget))
        let notifications = NotificationCenter.default
        notificationTokens.append(notifications.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self, let type else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    let wasPlaying = self.isPlaying
                    self.pause()
                    self.resumeAfterInterruption = wasPlaying
                } else {
                    let resume = self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if resume { self.play() }
                }
            }
        })
        notificationTokens.append(notifications.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.pause() }
            }
        })
        notificationTokens.append(notifications.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            let finished = notification.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self, finished === self.player.currentItem else { return }
                self.pause()
                self.currentTime = self.duration
                self.updateNowPlaying()
            }
        })
        updateNowPlaying()
    }

    static func preview(error: Bool = false) -> MediaPlayback {
        let defaults = UserDefaults(suiteName: "Amplifier.preview.\(UUID().uuidString)")!
        let model = MediaPlayback(defaults: defaults, systemControls: false)
        if error { model.errorMessage = MediaError.unplayable.errorDescription }
        return model
    }
}
