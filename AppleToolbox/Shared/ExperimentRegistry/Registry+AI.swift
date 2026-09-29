import Foundation

extension ExperimentRegistry {
    static let ai: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "natural-language", name: "Natural Language", category: .ai,
            description: "Identify the language, tokenize by word, sentence or paragraph, tag lexical classes and named entities, score sentiment, lemmatize, and compare words or sentences with the bundled NLEmbedding models, all on device.", frameworks: ["NaturalLanguage"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 12+ · macOS 10.14+ · watchOS 5+ · tvOS 12+ (sentiment iOS 13+, sentence embeddings iOS 14+)"], permissions: [], capabilities: ["On-device language models", "Tagger asset download (network)"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/naturallanguage")!, evaluate: { .available }),
        ExperimentDescriptor(id: "foundation-models", name: "Foundation Models", category: .ai,
            description: "Read the on-device model's availability and concrete reason, stream a reply to your own prompt, and generate a typed @Generable result with guided generation.", frameworks: ["FoundationModels"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Apple Intelligence-capable device"], osRequirements: ["iOS 26+ · macOS 26+ with Apple Intelligence enabled"], permissions: [], capabilities: ["Apple Intelligence", "On-device language model"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/foundationmodels")!, evaluate: ExperimentAvailability.foundationModels,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "This device is not eligible for Apple Intelligence.", required: "An Apple Intelligence-capable device",
                    nextStep: "Run on a device that supports Apple Intelligence."),
                .unavailable: ExperimentExplanation(reason: "Apple Intelligence is turned off (appleIntelligenceNotEnabled) or the model is still downloading (modelNotReady); the run section shows which.", required: "Apple Intelligence enabled with the model downloaded",
                    nextStep: "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri and wait for the model download to finish."),
            ]),
        ExperimentDescriptor(id: "speech", name: "Speech Recognition", category: .ai,
            description: "Use the real speech recognizer and microphone to transcribe live spoken words.", frameworks: ["Speech", "AVFAudio"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Microphone"], osRequirements: ["iOS 10+ · macOS 10.15+"], permissions: ["Speech Recognition", "Microphone Usage Description"], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/speech")!, evaluate: ExperimentAvailability.speech),
        ExperimentDescriptor(id: "core-ml", name: "Core ML", category: .ai,
            description: "List the CPU, GPU and Neural Engine Core ML can use, then import a .mlmodel, .mlpackage or .mlmodelc, compile it on device and inspect its inputs, outputs, metadata and compute units. No inference is run.", frameworks: ["CoreML", "Metal"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 17+ · macOS 14+"], permissions: ["User-selected file access"], capabilities: ["On-device model compilation", "Neural Engine where available"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/coreml")!, evaluate: { .available },
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Importing a model needs the system document picker, which Apple TV and Apple Watch do not offer; watchOS also cannot compile models on device.", required: "iOS, iPadOS or macOS",
                    nextStep: "Open the experiment on iPhone, iPad or Mac. On Apple TV the compute devices are still listed below."),
            ]),
        ExperimentDescriptor(id: "translation", name: "Translation", category: .ai,
            description: "Pick a language pair from the languages the system supports, check whether it is installed, supported or unsupported, and translate your own text with a real TranslationSession.", frameworks: ["Translation", "SwiftUI"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 18+ · macOS 15+"], permissions: [], capabilities: ["On-device language assets", "Language download (network)"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/translation")!, evaluate: { [.iOS, .iPadOS, .macOS].contains(CurrentPlatform.value) ? .available : .platformUnsupported }),
    ]
}
