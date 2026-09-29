import Foundation
import Combine
import CoreMedia
import AVFoundation
import MediaPlayer
#if os(iOS) || os(tvOS)
import AVKit
#endif

/// Apple's public HTTP Live Streaming examples (developer.apple.com › HTTP Live Streaming › Examples).
enum HLSSampleStream: String, CaseIterable, Identifiable {
    case basic16x9 = "BipBop 16:9 · basic (TS)"
    case basic4x3 = "BipBop 4:3 · basic (TS)"
    case advancedTS = "BipBop advanced (TS)"
    case advancedFMP4 = "BipBop advanced (fMP4)"

    var id: String { rawValue }

    var url: URL {
        let base = "https://devstreaming-cdn.apple.com/videos/streaming/examples/"
        return switch self {
        case .basic16x9: URL(string: base + "bipbop_16x9/bipbop_16x9_variant.m3u8")!
        case .basic4x3: URL(string: base + "bipbop_4x3/bipbop_4x3_variant.m3u8")!
        case .advancedTS: URL(string: base + "img_bipbop_adv_example_ts/master.m3u8")!
        case .advancedFMP4: URL(string: base + "img_bipbop_adv_example_fmp4/master.m3u8")!
        }
    }

    /// The next or previous stream, wrapping around; used for the next/previous track remote commands.
    func neighbor(offset: Int) -> HLSSampleStream {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[((index + offset) % all.count + all.count) % all.count]
    }
}

/// Which pair of skip buttons Control Center and the Lock Screen show; the system shows interval skips when both are enabled.
enum RemoteSkipStyle: String, CaseIterable, Identifiable {
    case interval = "Skip ±15 s"
    case track = "Previous / next stream"
    var id: String { rawValue }
}

nonisolated enum RemoteCommandKind: String, CaseIterable, Sendable {
    case play, pause, togglePlayPause, skipForward, skipBackward, nextTrack, previousTrack, changePlaybackPosition

    var title: String {
        switch self {
        case .play: "Play"
        case .pause: "Pause"
        case .togglePlayPause: "Toggle play/pause"
        case .skipForward: "Skip forward"
        case .skipBackward: "Skip backward"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .changePlaybackPosition: "Change playback position"
        }
    }

    func command(in center: MPRemoteCommandCenter) -> MPRemoteCommand {
        switch self {
        case .play: center.playCommand
        case .pause: center.pauseCommand
        case .togglePlayPause: center.togglePlayPauseCommand
        case .skipForward: center.skipForwardCommand
        case .skipBackward: center.skipBackwardCommand
        case .nextTrack: center.nextTrackCommand
        case .previousTrack: center.previousTrackCommand
        case .changePlaybackPosition: center.changePlaybackPositionCommand
        }
    }
}

/// The Sendable part of an MPRemoteCommandEvent.
nonisolated struct ReceivedRemoteCommand: Sendable {
    let kind: RemoteCommandKind
    let interval: TimeInterval?
    let position: TimeInterval?
}

nonisolated enum RemoteCommandHandler {
    /// Built outside the main actor because MediaPlayer does not document the handler's thread.
    /// On the main thread the command runs synchronously so the real status is returned; otherwise it hops.
    static func make(kind: RemoteCommandKind, deliver: @escaping @MainActor @Sendable (ReceivedRemoteCommand) -> MPRemoteCommandHandlerStatus) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { @Sendable event in
            let received = ReceivedRemoteCommand(kind: kind, interval: (event as? MPSkipIntervalCommandEvent)?.interval,
                                                 position: (event as? MPChangePlaybackPositionCommandEvent)?.positionTime)
            if Thread.isMainThread {
                return MainActor.assumeIsolated { deliver(received) }
            }
            Task { @MainActor in _ = deliver(received) }
            return .success
        }
    }
}

/// Plays Apple's HLS sample with AVPlayer, publishes Now Playing info, handles remote commands,
/// and reports AirPlay and audio route changes.
@MainActor
final class MediaPlaybackService: ObservableObject {
    @Published var stream = HLSSampleStream.basic16x9 {
        didSet { if isActive, stream != oldValue { load(stream, autoplay: true) } }
    }
    @Published var skipStyle = RemoteSkipStyle.interval {
        didSet { if isActive, skipStyle != oldValue { registerRemoteCommands() } }
    }
    @Published private(set) var output = "Start playback to load Apple's BipBop HLS sample, publish Now Playing info and listen for remote commands."
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackState = "Idle"
    @Published private(set) var itemStatus = "No item"
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double?
    @Published private(set) var isLiveStream = false
    @Published private(set) var videoSize = CGSize.zero
    @Published private(set) var indicatedBitrate: Double?
    @Published private(set) var observedBitrate: Double?
    @Published private(set) var stallCount = 0
    @Published private(set) var isExternalPlaybackActive = false
    @Published private(set) var multipleRoutesDetected = false
    @Published private(set) var nowPlaying: [AudioRouteDetail] = []
    @Published private(set) var route = AudioRouteInspector.snapshot()
    @Published private(set) var events: [AudioEventEntry] = []

    let player = AVPlayer()
    private let routeDetector = AVRouteDetector()
    private let routeMonitor = AudioRouteMonitor()
    private var playerCancellables: Set<AnyCancellable> = []
    private var itemCancellables: Set<AnyCancellable> = []
    private var timeObserver: Any?
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    func start() {
        guard !isActive else { return }
        do { try AudioSessionController.activateForPlayback(video: true) }
        catch { status = .unavailable; output = "Audio session error: \(error.localizedDescription)"; return }
        isActive = true
        status = .available
        observePlayer()
        registerRemoteCommands()
        startRouteObservation()
        log("Session started", "Audio session category Playback, mode Movie Playback (non-mixable), so this app can become the Now Playing app.")
        load(stream, autoplay: true)
    }

    func stop() {
        guard isActive else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemCancellables.removeAll()
        playerCancellables.removeAll()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        unregisterRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        routeDetector.isRouteDetectionEnabled = false
        routeMonitor.stop()
        AudioSessionController.deactivate()
        isActive = false
        isPlaying = false
        playbackState = "Idle"
        itemStatus = "No item"
        nowPlaying = []
        log("Session stopped", "Now Playing info cleared and remote command targets removed.")
        output = "Playback stopped. Now Playing info was cleared and the remote command handlers were removed."
    }

    func togglePlayPause() { isPlaying ? player.pause() : player.play() }

    func skip(by seconds: Double) {
        guard player.currentItem != nil else { return }
        seek(to: max(0, player.currentTime().seconds + seconds))
    }

    func refreshRoute() { route = AudioRouteInspector.snapshot() }

    /// Called by the AirPlay route picker's delegate.
    func routePickerPresented(_ presenting: Bool) {
        log(presenting ? "AirPlay picker opened" : "AirPlay picker closed", presenting ? "AVRoutePickerView is showing the available routes." : "Current output: \(AudioRouteInspector.snapshot().outputSummary)")
        refreshRoute()
    }

    // MARK: Player

    private func load(_ stream: HLSSampleStream, autoplay: Bool) {
        let item = AVPlayerItem(url: stream.url)
        #if os(iOS) || os(tvOS)
        item.externalMetadata = Self.metadata(for: stream)
        #endif
        observe(item)
        duration = nil
        currentTime = 0
        isLiveStream = false
        videoSize = .zero
        indicatedBitrate = nil
        observedBitrate = nil
        stallCount = 0
        itemStatus = "Loading"
        player.replaceCurrentItem(with: item)
        if autoplay { player.play() }
        publishNowPlaying()
        log("Loading \(stream.rawValue)", stream.url.absoluteString)
        output = "Loading \(stream.rawValue) from Apple's HLS examples…"
    }

    /// AVPlayer and AVPlayerItem deliver KVO on the main queue by default; receive(on:) keeps it that way.
    private func observePlayer() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.timeControlStatusChanged(status) }
            .store(in: &playerCancellables)
        player.publisher(for: \.isExternalPlaybackActive)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.isExternalPlaybackActive = active
                self?.log(active ? "AirPlay video started" : "AirPlay video ended", active ? "The video now plays on an external AirPlay device." : "The video plays on this device again.")
            }
            .store(in: &playerCancellables)
        routeDetector.publisher(for: \.multipleRoutesDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in self?.multipleRoutesDetected = detected }
            .store(in: &playerCancellables)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { @Sendable [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.currentTime = seconds.isFinite ? seconds : 0 }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        itemCancellables.removeAll()
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let item else { return }
                self?.itemStatusChanged(status, item: item)
            }
            .store(in: &itemCancellables)
        item.publisher(for: \.presentationSize)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in self?.videoSize = size }
            .store(in: &itemCancellables)
        let center = NotificationCenter.default
        center.publisher(for: AVPlayerItem.newAccessLogEntryNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let item else { return }
                self?.accessLogChanged(item)
            }
            .store(in: &itemCancellables)
        center.publisher(for: AVPlayerItem.playbackStalledNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.log("Playback stalled", "The buffer ran empty; AVPlayer waits for more data.") }
            .store(in: &itemCancellables)
        center.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.log("Played to end") }
            .store(in: &itemCancellables)
        center.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.log("Failed to play to end", error?.localizedDescription ?? "Unknown error")
            }
            .store(in: &itemCancellables)
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        guard isActive else { return }
        isPlaying = status == .playing
        playbackState = switch status {
        case .paused: "Paused"
        case .playing: "Playing"
        case .waitingToPlayAtSpecifiedRate: "Waiting · \(player.reasonForWaitingToPlay.map(Self.describe) ?? "buffering")"
        @unknown default: "Unknown"
        }
        publishNowPlaying()
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch status {
        case .readyToPlay:
            itemStatus = "Ready to play"
            isLiveStream = item.duration.isIndefinite
            duration = item.duration.isNumeric ? item.duration.seconds : nil
            self.status = .available
            output = "Playing \(stream.rawValue). Open Control Center or the Lock Screen to see the Now Playing entry and send commands."
            log("Ready to play", isLiveStream ? "Live stream" : "Duration \(Self.clock(duration ?? 0))")
            publishNowPlaying()
        case .failed:
            itemStatus = "Failed"
            self.status = .unavailable
            let error = item.error as NSError?
            output = "AVPlayerItem failed: \(error?.localizedDescription ?? "unknown error")\nDomain: \(error?.domain ?? "—") · Code: \(error?.code ?? 0)\nThe sample streams need network access to devstreaming-cdn.apple.com."
            log("Item failed", error?.localizedDescription ?? "Unknown error")
        case .unknown:
            itemStatus = "Loading"
        @unknown default:
            itemStatus = "Unknown"
        }
    }

    private func accessLogChanged(_ item: AVPlayerItem) {
        guard let event = item.accessLog()?.events.last else { return }
        let previous = indicatedBitrate
        indicatedBitrate = event.indicatedBitrate > 0 ? event.indicatedBitrate : nil
        observedBitrate = event.observedBitrate > 0 ? event.observedBitrate : nil
        stallCount = event.numberOfStalls
        if let indicated = indicatedBitrate, indicated != previous {
            log("Variant switch", "Indicated bitrate \(Self.bitrate(indicated)); observed \(observedBitrate.map(Self.bitrate) ?? "—")")
        }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { @Sendable [weak self] finished in
            Task { @MainActor in
                guard finished else { return }
                self?.currentTime = seconds
                self?.publishNowPlaying()
            }
        }
    }

    // MARK: Now Playing

    private func publishNowPlaying() {
        guard isActive else { return }
        let elapsed = player.currentTime().seconds
        let index = HLSSampleStream.allCases.firstIndex(of: stream) ?? 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: stream.rawValue,
            MPMediaItemPropertyArtist: "Apple HLS examples",
            MPMediaItemPropertyAlbumTitle: "Apple Toolbox · Media & Now Playing",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: Double(player.rate),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyAssetURL: stream.url,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: HLSSampleStream.allCases.count,
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
        nowPlaying = [
            AudioRouteDetail(label: "Title", value: stream.rawValue),
            AudioRouteDetail(label: "Artist", value: "Apple HLS examples"),
            AudioRouteDetail(label: "Media type", value: "Video"),
            AudioRouteDetail(label: "Duration", value: isLiveStream ? "Live" : duration.map(Self.clock) ?? "—"),
            AudioRouteDetail(label: "Elapsed (at publish)", value: Self.clock(elapsed.isFinite ? elapsed : 0)),
            AudioRouteDetail(label: "Playback rate", value: player.rate.formatted(.number.precision(.fractionLength(1)))),
            AudioRouteDetail(label: "Queue position", value: "\(index + 1) of \(HLSSampleStream.allCases.count)"),
        ]
    }

    // MARK: Remote commands

    private func registerRemoteCommands() {
        unregisterRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        let kinds: [RemoteCommandKind] = [.play, .pause, .togglePlayPause, .changePlaybackPosition]
            + (skipStyle == .interval ? [.skipForward, .skipBackward] : [.nextTrack, .previousTrack])
        for kind in RemoteCommandKind.allCases {
            let command = kind.command(in: center)
            command.isEnabled = kinds.contains(kind)
            guard kinds.contains(kind) else { continue }
            let token = command.addTarget(handler: RemoteCommandHandler.make(kind: kind) { [weak self] received in
                self?.handleRemoteCommand(received) ?? .noActionableNowPlayingItem
            })
            commandTargets.append((command, token))
        }
        log("Remote commands registered", kinds.map(\.title).joined(separator: ", "))
    }

    private func unregisterRemoteCommands() {
        for (command, token) in commandTargets { command.removeTarget(token) }
        commandTargets.removeAll()
        let center = MPRemoteCommandCenter.shared()
        RemoteCommandKind.allCases.forEach { $0.command(in: center).isEnabled = false }
    }

    private func handleRemoteCommand(_ command: ReceivedRemoteCommand) -> MPRemoteCommandHandlerStatus {
        var detail = "MPRemoteCommandCenter"
        if let interval = command.interval { detail += " · interval \(Int(interval)) s" }
        if let position = command.position { detail += " · position \(Self.clock(position))" }
        log("Remote command: \(command.kind.title)", detail)
        guard isActive, player.currentItem != nil else { return .noActionableNowPlayingItem }
        switch command.kind {
        case .play: player.play()
        case .pause: player.pause()
        case .togglePlayPause: togglePlayPause()
        case .skipForward: skip(by: command.interval ?? 15)
        case .skipBackward: skip(by: -(command.interval ?? 15))
        case .nextTrack: stream = stream.neighbor(offset: 1)
        case .previousTrack: stream = stream.neighbor(offset: -1)
        case .changePlaybackPosition:
            guard let position = command.position, !isLiveStream else { return .commandFailed }
            seek(to: position)
        }
        return .success
    }

    // MARK: Routes

    private func startRouteObservation() {
        routeDetector.isRouteDetectionEnabled = true
        routeMonitor.start { [weak self] event in
            guard let self else { return }
            events.insert(event.entry, at: 0)
            trimEvents()
            refreshRoute()
        }
        refreshRoute()
    }

    private func log(_ title: String, _ detail: String = "") {
        events.insert(AudioEventEntry(title: title, detail: detail), at: 0)
        trimEvents()
    }

    private func trimEvents() {
        if events.count > 50 { events.removeLast(events.count - 50) }
    }

    // MARK: Formatting

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded(.down))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1_000_000
            ? (bitsPerSecond / 1_000_000).formatted(.number.precision(.fractionLength(2))) + " Mbit/s"
            : (bitsPerSecond / 1_000).formatted(.number.precision(.fractionLength(0))) + " kbit/s"
    }

    private static func describe(_ reason: AVPlayer.WaitingReason) -> String {
        switch reason {
        case .toMinimizeStalls: "buffering to minimize stalls"
        case .evaluatingBufferingRate: "evaluating the buffering rate"
        case .noItemToPlay: "no item to play"
        default: reason.rawValue
        }
    }

    #if os(iOS) || os(tvOS)
    /// Shown by AVPlayerViewController; on tvOS it also feeds the system's Now Playing entry.
    private static func metadata(for stream: HLSSampleStream) -> [AVMetadataItem] {
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = stream.rawValue as NSString
        title.extendedLanguageTag = "und"
        let description = AVMutableMetadataItem()
        description.identifier = .commonIdentifierDescription
        description.value = "Apple's public HTTP Live Streaming example, played by Apple Toolbox." as NSString
        description.extendedLanguageTag = "und"
        return [title, description]
    }
    #endif
}
