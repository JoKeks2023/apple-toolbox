import SwiftUI
import AVKit

extension MediaPlaybackService: StoppableExperiment {}

struct MediaPlaybackRunView: View {
    @StateObject private var media = MediaPlaybackService()
    #if os(tvOS)
    @State private var isShowingPlayer = false
    #endif

    var body: some View {
        Picker("Stream", selection: $media.stream) {
            ForEach(HLSSampleStream.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Remote skip buttons", selection: $media.skipStyle) {
            ForEach(RemoteSkipStyle.allCases) { Text($0.rawValue).tag($0) }
        }
        HStack {
            Button(media.isActive ? "Stop Session" : "Start Playback", systemImage: media.isActive ? "stop.circle" : "play.rectangle") {
                media.isActive ? media.stop() : media.start()
            }
            .buttonStyle(.borderedProminent)
            .experimentSession(media)
            if media.isActive {
                Button("Back 15 s", systemImage: "gobackward.15") { media.skip(by: -15) }
                    .labelStyle(.iconOnly)
                Button(media.isPlaying ? "Pause" : "Play", systemImage: media.isPlaying ? "pause.fill" : "play.fill", action: media.togglePlayPause)
                    .labelStyle(.iconOnly)
                Button("Forward 15 s", systemImage: "goforward.15") { media.skip(by: 15) }
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
        if media.isActive {
            #if os(tvOS)
            Button("Watch Full Screen", systemImage: "tv") { isShowingPlayer = true }
                .experimentFullScreenCover(isPresented: $isShowingPlayer) {
                    PlayerSurface(player: media.player).ignoresSafeArea()
                }
            #else
            PlayerSurface(player: media.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            #endif
        }
        AirPlayRow(media: media)
        OutputView(text: media.output, isError: media.status == .unavailable)
        PlaybackDetailsSection(media: media)
        NowPlayingSection(media: media)
        AudioRouteSection(route: media.route, refresh: media.refreshRoute)
        Section("Remote commands and route changes") {
            AudioEventLogView(events: media.events, emptyText: "Start playback, then use play, pause or skip in Control Center, on the Lock Screen, on headphones or with the Siri Remote. Every command MPRemoteCommandCenter delivers appears here, together with route changes.")
        }
    }
}

private struct AirPlayRow: View {
    @ObservedObject var media: MediaPlaybackService

    var body: some View {
        LabeledContent {
            RoutePicker(player: media.player, presented: media.routePickerPresented)
                .frame(width: 44, height: 44)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("AirPlay · AVRoutePickerView")
                Text(media.isActive
                     ? "Other routes detected: \(media.multipleRoutesDetected ? "yes" : "no") · AirPlay video: \(media.isExternalPlaybackActive ? "active" : "inactive")"
                     : "Route detection (AVRouteDetector) runs while playback is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PlaybackDetailsSection: View {
    @ObservedObject var media: MediaPlaybackService

    var body: some View {
        Section("Playback · AVPlayer") {
            LabeledContent("State", value: media.playbackState)
            LabeledContent("Item", value: media.itemStatus)
            LabeledContent("Position") {
                Text("\(MediaPlaybackService.clock(media.currentTime)) / \(media.isLiveStream ? "Live" : media.duration.map(MediaPlaybackService.clock) ?? "—")")
                    .font(.body.monospacedDigit())
            }
            LabeledContent("Video size", value: media.videoSize == .zero ? "—" : "\(Int(media.videoSize.width)) × \(Int(media.videoSize.height))")
            LabeledContent("Indicated bitrate", value: media.indicatedBitrate.map(MediaPlaybackService.bitrate) ?? "—")
            LabeledContent("Observed bitrate", value: media.observedBitrate.map(MediaPlaybackService.bitrate) ?? "—")
            LabeledContent("Stalls", value: "\(media.stallCount)")
        }
    }
}

private struct NowPlayingSection: View {
    @ObservedObject var media: MediaPlaybackService

    var body: some View {
        Section("Now Playing · MPNowPlayingInfoCenter") {
            if media.nowPlaying.isEmpty {
                Text("Nothing published. Start playback to publish Now Playing info.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(media.nowPlaying) { LabeledContent($0.label, value: $0.value) }
            Text(Self.platformNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static var platformNote: String {
        #if os(iOS)
        "AVPlayerViewController's own Now Playing updates are off, so this entry comes from the experiment. Open Control Center while the app plays. Apple Toolbox declares no audio background mode: when it leaves the foreground, iOS suspends it and the entry shows the paused item, and Lock Screen commands cannot resume it."
        #elseif os(tvOS)
        "In full screen, AVPlayerViewController also publishes Now Playing from the item's external metadata and handles the Siri Remote itself. Commands from Control Center or the Apple TV Remote in iOS arrive through MPRemoteCommandCenter."
        #else
        "AVPlayerView's own Now Playing updates are off, so this entry comes from the experiment, including playbackState. It appears in Control Center › Now Playing and responds to the media keys."
        #endif
    }
}

/// AVKit playback surface: AVPlayerViewController on iOS and tvOS, AVPlayerView on macOS.
private struct PlayerSurface {
    let player: AVPlayer
}

#if os(iOS) || os(tvOS)
extension PlayerSurface: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        #if os(iOS)
        // The experiment publishes Now Playing itself; picture in picture would need the audio background mode.
        controller.updatesNowPlayingInfoCenter = false
        controller.allowsPictureInPicturePlayback = false
        #endif
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
#elseif os(macOS)
extension PlayerSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.updatesNowPlayingInfoCenter = false
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#endif

/// The system AirPlay button. Its delegate reports when the route list opens and closes.
private struct RoutePicker {
    let player: AVPlayer
    let presented: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(presented: presented) }

    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        let presented: (Bool) -> Void
        init(presented: @escaping (Bool) -> Void) { self.presented = presented }
        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) { presented(true) }
        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) { presented(false) }
    }
}

#if os(iOS) || os(tvOS)
extension RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
#elseif os(macOS)
extension RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
#endif
