import Foundation

extension ExperimentRegistry {
    static let audio: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "audio-input", name: "Audio Analyzer", category: .audio,
            description: "Generate sine, square, sawtooth or noise tones with AVAudioSourceNode through an EQ, distortion, delay and reverb chain, inspect the output route, sample rate, IO buffer and latency, follow route changes, and analyze the microphone with a live vDSP FFT spectrum and RMS/peak meter.",
            frameworks: ["AVFAudio", "Accelerate", "AVFoundation", "CoreAudio"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Speaker or headphones", "Microphone (spectrum and meter)"], osRequirements: ["iOS 13+ · macOS 10.15+ (AVAudioSourceNode)", "Route timing: AVAudioSession on iOS, Core Audio HAL on macOS"], permissions: ["Microphone Usage Description (spectrum and meter only)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/avfaudio/avaudioengine")!, evaluate: ExperimentAvailability.microphone,
            useCase: ExperimentUseCase(id: "audio-analyzer", title: "Audio Analyzer", summary: "Use the device as a signal generator and spectrum analyzer: play a test tone through real AVAudioUnit effects and measure what the microphone hears.", interaction: "Pick a waveform, frequency and volume, play the tone and switch effect presets; start the microphone to see the FFT spectrum, the dominant frequency and the level meter, and plug in headphones to watch the route change."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "No microphone is available, so the spectrum and level meter have no input. The tone generator, effects and route information still work.", required: "A built-in or connected microphone",
                    nextStep: "Connect a microphone (Mac) or run the experiment on an iPhone or iPad."),
                .permissionDenied: ExperimentExplanation(reason: "Microphone access is denied, so the spectrum and level meter cannot read input. The tone generator, effects and route information still work.", required: "Microphone access for Apple Toolbox",
                    nextStep: "Allow the microphone in Settings › Privacy & Security › Microphone."),
                .platformUnsupported: ExperimentExplanation(reason: "The analyzer measures the device microphone, which Apple Toolbox only uses on iPhone, iPad and Mac.", required: "iOS, iPadOS or macOS",
                    nextStep: "Open Apple Toolbox on iPhone, iPad or Mac."),
            ]),
        ExperimentDescriptor(id: "sound-analysis", name: "Sound Analysis", category: .audio,
            description: "Classify live microphone audio with Apple's built-in sound classifier and watch the top three labels and their confidence update in real time.", frameworks: ["SoundAnalysis", "AVFAudio"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Microphone"], osRequirements: ["iOS 15+ · macOS 12+"], permissions: ["Microphone Usage Description"], capabilities: ["Built-in sound classifier (version 1)"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/soundanalysis")!, evaluate: ExperimentAvailability.microphone,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "No microphone is available to this app, so there is no audio stream to classify.", required: "A built-in or connected microphone",
                    nextStep: "Connect a microphone (Mac) or run the experiment on an iPhone or iPad."),
            ]),
        ExperimentDescriptor(id: "media-playback", name: "Media & Now Playing", category: .audio,
            description: "Play Apple's public BipBop HLS stream with AVKit, publish Now Playing info with MPNowPlayingInfoCenter, receive play, pause, skip and scrub commands through MPRemoteCommandCenter, choose an AirPlay route with AVRoutePickerView, and log route changes.",
            frameworks: ["AVKit", "AVFoundation", "MediaPlayer"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: ["Network access to devstreaming-cdn.apple.com", "AirPlay receiver on the same network (optional)"], osRequirements: ["iOS 13+ · macOS 10.15+ · tvOS 13+"], permissions: [], capabilities: ["Non-mixable Playback audio session (to become the Now Playing app)"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "now-playing-lab", title: "Become the Now Playing app", summary: "See what an app has to do to show up in Control Center, on the Lock Screen and on Apple TV: AVKit playback, Now Playing info, remote commands and AirPlay.", interaction: "Start playback, open Control Center (or use the Siri Remote on Apple TV) and play, pause or skip there; each command appears in the log. Switch the skip buttons, pick an AirPlay device and connect headphones to watch the route change."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Apple Toolbox plays video with AVKit and handles remote commands only on iPhone, iPad, Mac and Apple TV.", required: "iOS, iPadOS, macOS or tvOS",
                    nextStep: "Open Apple Toolbox on iPhone, iPad, Mac or Apple TV."),
            ]),
        ExperimentDescriptor(id: "musickit", name: "MusicKit", category: .audio,
            description: "Authorize MusicKit, read the Apple Music subscription and storefront, search the catalog for songs, albums, artists and playlists, read your library and its playlists, and play or queue items with ApplicationMusicPlayer where the account allows it.",
            frameworks: ["MusicKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS, .watchOS], hardwareRequirements: [],
            osRequirements: ["Catalog search: iOS 15+ · macOS 12+ · tvOS 15+", "Library requests: iOS 16+ · macOS 14+ · tvOS 16+", "ApplicationMusicPlayer: iOS 15+ · macOS 14+ · tvOS 15+ (not on watchOS)"],
            permissions: ["Apple Music authorization (NSAppleMusicUsageDescription)"], capabilities: ["MusicKit App Service for the App ID", "Apple Music subscription for full catalog playback"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/musickit")!, evaluate: ExperimentAvailability.musicKit,
            useCase: ExperimentUseCase(id: "musickit-browse-play", title: "Search and play Apple Music", summary: "See what MusicKit gives this app for your account: subscription state, catalog search, your library and playlists, and in-app playback.", interaction: "Authorize, pick catalog or library and a type, search or load, open an album or playlist to list its tracks, then play or queue items and control ApplicationMusicPlayer. Without a subscription, catalog playback fails with the real error."),
            explanations: [
                .permissionRequired: ExperimentExplanation(reason: "Apple Music access has not been granted, so MusicKit returns no account, catalog or library data.", required: "Apple Music authorization for Apple Toolbox",
                    nextStep: "Tap Request MusicKit Authorization and allow access."),
                .permissionDenied: ExperimentExplanation(reason: "Apple Music access is denied or restricted, so MusicKit requests fail.", required: "Apple Music authorization for Apple Toolbox",
                    nextStep: "Allow Apple Toolbox in Settings › Privacy & Security › Media & Apple Music, or lift the Screen Time restriction."),
            ],
            applePrograms: ["Apple Developer Program: the MusicKit App Service must be enabled for the App ID in Certificates, Identifiers & Profiles (MusicKit then issues the developer token automatically)"]),
        ExperimentDescriptor(id: "shazamkit", name: "ShazamKit", category: .audio,
            description: "Listen through the microphone with SHManagedSession and identify the playing song in the Shazam catalog: title, artist, genres and Apple Music links, or the real no-match or error result.", frameworks: ["ShazamKit", "AVFoundation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Microphone and a nearby audio source"], osRequirements: ["iOS 17+ · macOS 14+"], permissions: ["Microphone Usage Description"], capabilities: ["ShazamKit App Service for the App ID", "Network access to the Shazam catalog"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/shazamkit")!, evaluate: ExperimentAvailability.microphone,
            useCase: ExperimentUseCase(id: "shazam-identify", title: "Identify a song", summary: "Let ShazamKit listen through the microphone and match what is playing against the Shazam catalog.", interaction: "Play music nearby, start listening, and inspect the matched title, artist, genres and links, or the real no-match or error result."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "No microphone input is available, so ShazamKit has no audio to match.", required: "A built-in or connected microphone",
                    nextStep: "Connect a microphone or run the experiment on iPhone, iPad or a Mac with a microphone."),
                .platformUnsupported: ExperimentExplanation(reason: "This experiment records from the device microphone, which Apple Toolbox only uses on iPhone, iPad and Mac.", required: "iOS, iPadOS or macOS",
                    nextStep: "Open Apple Toolbox on iPhone, iPad or Mac."),
            ]),
    ]
}
