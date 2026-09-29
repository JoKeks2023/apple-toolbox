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
        ExperimentDescriptor(id: "musickit", name: "MusicKit", category: .audio,
            description: "Request real MusicKit authorization without pretending that a user account or library is available.", frameworks: ["MusicKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: [], osRequirements: ["Current supported OS"], permissions: ["Apple Music authorization"], capabilities: ["Apple Music"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/musickit")!, evaluate: ExperimentAvailability.musicKit),
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
