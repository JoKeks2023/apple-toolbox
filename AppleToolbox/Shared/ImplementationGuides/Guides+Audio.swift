import Foundation

nonisolated extension ImplementationGuides {
    static let audio: [String: ImplementationGuide] = [
        "audio-input": ImplementationGuide(
            snippet: #"""
            import Accelerate
            import AVFoundation

            /// Measures the microphone level in dBFS with AVAudioEngine and vDSP.
            @MainActor
            final class MicrophoneMeter {
                private let engine = AVAudioEngine()

                func start(onLevel: @escaping @Sendable (Float) -> Void) async throws {
                    guard await AVAudioApplication.requestRecordPermission() else { return }
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    Self.installTap(on: engine.inputNode, onLevel: onLevel)
                    try engine.start()
                }

                func stop() {
                    engine.inputNode.removeTap(onBus: 0)
                    engine.stop()
                }

                /// nonisolated: the tap block runs on the real-time audio thread, not on the main actor.
                private nonisolated static func installTap(on input: AVAudioInputNode, onLevel: @escaping @Sendable (Float) -> Void) {
                    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                        guard let samples = buffer.floatChannelData?[0] else { return }
                        var rms: Float = 0
                        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
                        onLevel(20 * log10(max(rms, .ulpOfOne)))
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSMicrophoneUsageDescription", value: "Measures the sound level around you."),
            ],
            notes: [
                "Don't allocate, lock or touch UI inside the tap; hand values to the main actor in a Task and throttle updates.",
                "Generate tones with an AVAudioSourceNode render block attached to the same engine and connected to mainMixerNode.",
                "Observe AVAudioSession.routeChangeNotification and interruptionNotification to restart the engine after headphones or calls.",
            ]
        ),
        "sound-analysis": ImplementationGuide(
            snippet: #"""
            import AVFoundation
            import SoundAnalysis

            /// Receives results on the analyzer's thread.
            final class ClassificationObserver: NSObject, SNResultsObserving, Sendable {
                let onResult: @Sendable ([(label: String, confidence: Double)]) -> Void
                init(onResult: @escaping @Sendable ([(label: String, confidence: Double)]) -> Void) { self.onResult = onResult }

                func request(_ request: SNRequest, didProduce result: SNResult) {
                    guard let result = result as? SNClassificationResult else { return }
                    onResult(result.classifications.prefix(3).map { ($0.identifier, $0.confidence) })
                }
            }

            @MainActor
            final class SoundClassifier {
                private let engine = AVAudioEngine()
                private var observer: ClassificationObserver?

                func start(onResult: @escaping @Sendable ([(label: String, confidence: Double)]) -> Void) throws {
                    try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
                    try AVAudioSession.sharedInstance().setActive(true)
                    let format = engine.inputNode.outputFormat(forBus: 0)
                    let analyzer = SNAudioStreamAnalyzer(format: format)
                    let observer = ClassificationObserver(onResult: onResult)
                    try analyzer.add(SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: observer)
                    self.observer = observer
                    Self.installTap(on: engine.inputNode, format: format, analyzer: analyzer)
                    try engine.start()
                }

                private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, analyzer: SNAudioStreamAnalyzer) {
                    input.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
                        analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSMicrophoneUsageDescription", value: "Listens to recognize sounds around you."),
            ],
            notes: [
                "SNClassifySoundRequest(classifierIdentifier: .version1) recognizes about 300 sounds; knownClassifications lists them.",
                "Results arrive on a background thread: hop to the main actor before updating UI.",
                "Tune windowDuration and overlapFactor on the request to trade latency against accuracy.",
            ]
        ),
        "media-playback": ImplementationGuide(
            snippet: #"""
            import AVFoundation
            import MediaPlayer

            /// Plays an HLS stream and shows it in Control Center and on the Lock Screen.
            @MainActor
            final class NowPlayingPlayer {
                let player = AVPlayer(url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")!)

                func play(title: String) throws {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try AVAudioSession.sharedInstance().setActive(true)

                    let commands = MPRemoteCommandCenter.shared()
                    commands.playCommand.addTarget { [weak self] _ in
                        self?.player.play()
                        return .success
                    }
                    commands.pauseCommand.addTarget { [weak self] _ in
                        self?.player.pause()
                        return .success
                    }

                    player.play()
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
                        MPMediaItemPropertyTitle: title,
                        MPNowPlayingInfoPropertyIsLiveStream: false,
                        MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime().seconds,
                        MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                    ]
                }
            }
            """#,
            capabilities: ["Background Modes › Audio, AirPlay, and Picture in Picture (to keep playing in the background)"],
            notes: [
                "Now Playing only appears with the .playback category, an active session and at least one enabled remote command.",
                "Update elapsed time and rate whenever playback state changes; the system extrapolates between updates.",
                "Add AVRoutePickerView (or AVPlayerViewController) for the AirPlay route picker.",
            ]
        ),
        "musickit": ImplementationGuide(
            snippet: #"""
            import MusicKit

            /// Searches the Apple Music catalog and plays the first song if the subscription allows it.
            @MainActor
            final class MusicSearch {
                func searchAndPlay(_ term: String) async throws {
                    guard await MusicAuthorization.request() == .authorized else { return }

                    var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                    request.limit = 5
                    let response = try await request.response()
                    guard let song = response.songs.first else { return }
                    print(song.title, song.artistName)

                    let subscription = try await MusicSubscription.current
                    guard subscription.canPlayCatalogContent else { return }

                    let player = ApplicationMusicPlayer.shared
                    player.queue = [song]
                    try await player.play()
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSAppleMusicUsageDescription", value: "Searches and plays music from your Apple Music library."),
            ],
            capabilities: ["Enable the MusicKit App Service for the App ID in the developer portal (Identifiers › App Services)"],
            notes: [
                "Catalog search needs no subscription; playback does (MusicSubscription.canPlayCatalogContent).",
                "The developer token is generated automatically once the MusicKit App Service is enabled; there is no entitlement to add.",
                "Library requests (MusicLibraryRequest) need authorization and show only what the user has added.",
            ]
        ),
        "shazamkit": ImplementationGuide(
            snippet: #"""
            import ShazamKit

            /// Listens through the microphone and matches the song against the Shazam catalog.
            @MainActor
            final class SongIdentifier {
                private let session = SHManagedSession()

                func identify() async -> String {
                    switch await session.result() {
                    case .match(let match):
                        guard let item = match.mediaItems.first else { return "Match without metadata" }
                        return "\(item.title ?? "Unknown title") – \(item.artist ?? "Unknown artist")"
                    case .noMatch:
                        return "No match"
                    case .error(let error, _):
                        return "Error: \(error.localizedDescription)"
                    }
                }

                func cancel() { session.cancel() }
            }
            """#,
            infoPlist: [
                .init(key: "NSMicrophoneUsageDescription", value: "Listens to identify the song that is playing."),
            ],
            capabilities: ["Enable the ShazamKit App Service for the App ID in the developer portal (Identifiers › App Services)"],
            notes: [
                "SHManagedSession (iOS 17+) records and configures the audio session itself; call prepare() to start faster.",
                "Use session.results for continuous matching instead of a single result().",
                "Custom catalogs (SHCustomCatalog) match your own audio without the catalog service.",
            ]
        ),
    ]
}
