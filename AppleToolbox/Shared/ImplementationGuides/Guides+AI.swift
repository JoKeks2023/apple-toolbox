import Foundation

nonisolated extension ImplementationGuides {
    static let ai: [String: ImplementationGuide] = [
        "natural-language": ImplementationGuide(
            snippet: #"""
            import NaturalLanguage

            /// Detects the language, finds names and places, and scores the sentiment of a text, all on device.
            func analyze(_ text: String) -> (language: NLLanguage?, entities: [(String, NLTag)], sentiment: Double) {
                let language = NLLanguageRecognizer.dominantLanguage(for: text)

                let tagger = NLTagger(tagSchemes: [.nameType, .sentimentScore])
                tagger.string = text
                var entities: [(String, NLTag)] = []
                let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
                tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
                    if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                        entities.append((String(text[range]), tag))
                    }
                    return true
                }

                let (score, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
                return (language, entities, Double(score?.rawValue ?? "0") ?? 0)
            }

            /// Cosine distance between two words with the bundled word embedding (nil if the language has none).
            func distance(_ a: String, _ b: String) -> Double? {
                NLEmbedding.wordEmbedding(for: .english)?.distance(between: a, and: b)
            }
            """#,
            notes: [
                "NLTagger and NLEmbedding work synchronously; run them off the main actor for long texts.",
                "Tagger models for some languages are downloaded on demand; check NLTagger.availableTagSchemes(for:language:) first.",
                "NLEmbedding.wordEmbedding(for:) returns nil for languages without a bundled model.",
            ]
        ),
        "foundation-models": ImplementationGuide(
            snippet: #"""
            import FoundationModels

            @Generable
            struct TripIdea {
                @Guide(description: "A short, catchy title")
                var title: String
                @Guide(description: "Three activities for the day", .count(3))
                var activities: [String]
            }

            @MainActor
            final class Assistant {
                private let session = LanguageModelSession(instructions: "You are a concise travel assistant.")

                /// Check before showing the feature: the model can be off, downloading or unsupported.
                var isAvailable: Bool {
                    if case .available = SystemLanguageModel.default.availability { return true }
                    return false
                }

                /// Streams a free-text reply; each snapshot contains the full text so far.
                func stream(_ prompt: String, onPartial: (String) -> Void) async throws {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        onPartial(snapshot.content)
                    }
                }

                /// Guided generation: the reply arrives as a typed value.
                func idea(for city: String) async throws -> TripIdea {
                    try await session.respond(to: "Plan a day in \(city).", generating: TripIdea.self).content
                }
            }
            """#,
            notes: [
                "Needs an Apple Intelligence-capable device with Apple Intelligence turned on; handle every SystemLanguageModel.Availability reason.",
                "One session handles one request at a time (isResponding); start another request only when the previous one has finished.",
                "Check SystemLanguageModel.default.supportsLocale(_:) for the user's language before prompting.",
            ]
        ),
        "foundation-models-tools": ImplementationGuide(
            snippet: #"""
            import FoundationModels

            /// A tool the model may call; its output is added to the transcript and used in the answer.
            struct WeatherTool: Tool {
                let name = "getWeather"
                let description = "Returns the current temperature in a city."

                @Generable
                struct Arguments {
                    @Guide(description: "The city name")
                    var city: String
                }

                func call(arguments: Arguments) async throws -> String {
                    "It is 21 °C in \(arguments.city)." // Call your real service here.
                }
            }

            @MainActor
            final class ToolChat {
                private let model = SystemLanguageModel.default
                private lazy var session = LanguageModelSession(model: model, tools: [WeatherTool()],
                                                                instructions: "Use getWeather for weather questions.")

                /// Every call continues the same conversation (multi-turn).
                func send(_ message: String) async throws -> String {
                    try await session.respond(to: message).content
                }

                /// Tokens used so far against the model's context window (iOS 26.4+).
                func usage() async throws -> (used: Int, limit: Int) {
                    (try await model.tokenCount(for: session.transcript), model.contextSize)
                }
            }
            """#,
            notes: [
                "Tools run off the main actor; make them Sendable and hop to the main actor explicitly for UI state.",
                "A long conversation eventually throws exceededContextWindowSize: start a new session, seeded with a summary of the transcript.",
                "Tool names, descriptions and argument schemas count against the context window too.",
            ]
        ),
        "foundation-models-image": ImplementationGuide(
            snippet: #"""
            import CoreGraphics
            import FoundationModels
            import Vision

            /// Asks the on-device model about a photo; it may call Vision's OCR and barcode tools (iOS 27+).
            @available(iOS 27.0, *)
            func ask(_ question: String, about image: CGImage) async throws -> String? {
                let model = SystemLanguageModel.default
                guard model.capabilities.contains(.vision) else { return nil }

                let session = LanguageModelSession(
                    model: model,
                    tools: [OCRTool(), BarcodeReaderTool()],
                    instructions: "Answer questions about the attached photo, labeled \"photo\"."
                )
                let stream = session.streamResponse {
                    question
                    Attachment(image).label("photo")
                }
                var answer = ""
                for try await snapshot in stream { answer = snapshot.content }
                return answer
            }
            """#,
            notes: [
                "Image input is new in iOS 27 and needs a model whose capabilities contain .vision; gate the feature on both.",
                "Scale large photos down (e.g. 2048 px longest side) and apply the EXIF orientation before attaching them.",
                "PhotosPicker needs no permission; the photo library usage key is only required for direct PHPhotoLibrary access.",
            ]
        ),
        "core-ai": ImplementationGuide(
            snippet: #"""
            import CoreAI
            import Foundation

            /// Specializes an .aimodel for this device and runs one of its functions (iOS 27+).
            @available(iOS 27.0, *)
            func runModel(at url: URL, function name: String, input: [Float], shape: [Int]) async throws -> NDArray? {
                guard AIModelAsset.isValid(at: url) else { return nil }
                // The first load compiles for this device; later loads reuse AIModelCache.
                let options = SpecializationOptions(preferredComputeUnitKind: .neuralEngine)
                let model = try await AIModel(contentsOf: url, options: options)

                guard let descriptor = model.functionDescriptor(for: name),
                      let inputName = descriptor.inputNames.first,
                      let outputName = descriptor.outputNames.first,
                      let function = try model.loadFunction(named: name) else { return nil }

                var outputs = try await function.run(inputs: [inputName: NDArray(scalars: input, shape: shape)])
                return outputs.remove(outputName)?.ndArray
            }
            """#,
            notes: [
                "Core AI is iOS 27 / macOS 27 only and absent from the Simulator SDK: guard with #if canImport(CoreAI) and #available.",
                "Specialization can take seconds; do it once, off the main actor, and keep the AIModel around.",
                "ComputeUnitKind.availableKinds tells which of CPU, GPU and Neural Engine this device offers.",
            ]
        ),
        "speech": ImplementationGuide(
            snippet: #"""
            import AVFoundation
            import Speech

            @MainActor
            final class LiveTranscriber {
                private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                private let engine = AVAudioEngine()
                private var task: SFSpeechRecognitionTask?

                func start(onText: @escaping @Sendable (String) -> Void) async throws {
                    let status = await withCheckedContinuation { continuation in
                        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                    }
                    guard status == .authorized, let recognizer, recognizer.isAvailable,
                          await AVAudioApplication.requestRecordPermission() else { return }

                    try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
                    try AVAudioSession.sharedInstance().setActive(true)
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
                    Self.feed(engine.inputNode, into: request)
                    try engine.start()
                    task = Self.recognize(request, with: recognizer, onText: onText)
                }

                func stop() {
                    engine.stop()
                    engine.inputNode.removeTap(onBus: 0)
                    task?.finish()
                }

                // nonisolated: both closures run on background threads, not on the main actor.
                private nonisolated static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
                    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                        request.append(buffer)
                    }
                }

                private nonisolated static func recognize(_ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer,
                                                          onText: @escaping @Sendable (String) -> Void) -> SFSpeechRecognitionTask {
                    recognizer.recognitionTask(with: request) { result, _ in
                        if let result { onText(result.bestTranscription.formattedString) }
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSSpeechRecognitionUsageDescription", value: "Turns what you say into text."),
                .init(key: "NSMicrophoneUsageDescription", value: "Listens to your voice to transcribe it."),
            ],
            notes: [
                "Server-based recognition is rate-limited and limited to about a minute per request; prefer on-device where supported.",
                "The recognition callback arrives on a background queue: hop to the main actor before touching UI state.",
                "On iOS 26+ SpeechAnalyzer with SpeechTranscriber is the modern, fully on-device replacement.",
            ]
        ),
        "speech-analyzer": ImplementationGuide(
            snippet: #"""
            import AVFoundation
            import Speech

            /// Transcribes an audio file on device with SpeechAnalyzer and SpeechTranscriber (iOS 26+).
            func transcribe(fileAt url: URL, locale: Locale = Locale(identifier: "en-US")) async throws -> String {
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                                    reportingOptions: [], attributeOptions: [.audioTimeRange])
                // Downloads the locale's model once; later calls return nil.
                if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await installation.downloadAndInstall()
                }

                let analyzer = SpeechAnalyzer(modules: [transcriber])
                let collector = Task {
                    var text = ""
                    for try await result in transcriber.results where result.isFinal {
                        text += String(result.text.characters)
                    }
                    return text
                }

                let file = try AVAudioFile(forReading: url)
                if let lastSample = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                return try await collector.value
            }
            """#,
            infoPlist: [
                .init(key: "NSMicrophoneUsageDescription", value: "Listens to your voice to transcribe it on this device."),
            ],
            notes: [
                "Check SpeechTranscriber.supportedLocales and AssetInventory before offering a language; the model download needs a network once.",
                "For live audio, convert microphone buffers to SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:) and yield AnalyzerInput into an AsyncStream.",
                "Add .volatileResults to reportingOptions to show fast guesses that are later replaced by final text.",
            ]
        ),
        "core-ml": ImplementationGuide(
            snippet: #"""
            import CoreML

            /// Compiles a model file, loads it for the Neural Engine where possible and runs one prediction.
            func predict(modelAt url: URL, input: [String: Any]) async throws -> MLFeatureProvider {
                // .mlmodel and .mlpackage must be compiled first; cache the .mlmodelc instead of compiling every launch.
                let compiledURL = try await MLModel.compileModel(at: url)

                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine
                let model = try await MLModel.load(contentsOf: compiledURL, configuration: configuration)

                print("Inputs:", model.modelDescription.inputDescriptionsByName.keys.sorted())
                let features = try MLDictionaryFeatureProvider(dictionary: input)
                return try await model.prediction(from: features)
            }

            /// The CPU, GPU and Neural Engine Core ML can use on this device.
            func computeDevices() -> [MLComputeDevice] {
                MLComputeDevice.allComputeDevices
            }
            """#,
            notes: [
                "Models added to the Xcode project are compiled at build time and get a generated Swift class; runtime compilation is for downloaded models.",
                "The first prediction includes warm-up; measure the median of several runs when comparing compute units.",
                "The Neural Engine is not available in the Simulator.",
            ]
        ),
        "create-ml": ImplementationGuide(
            snippet: #"""
            import CreateML
            import Foundation
            import TabularData

            /// Trains a text classifier on device from a CSV with "text" and "label" columns and saves it as .mlmodel.
            func trainClassifier(csv: URL, saveTo output: URL) throws -> Double {
                let data = try DataFrame(contentsOfCSVFile: csv)
                let (training, validation) = data.randomSplit(by: 0.8, seed: 42)

                let classifier = try MLTextClassifier(trainingData: DataFrame(training),
                                                      textColumn: "text", labelColumn: "label")
                let evaluation = classifier.evaluation(on: DataFrame(validation), textColumn: "text", labelColumn: "label")
                try classifier.write(to: output)

                print(try classifier.prediction(from: "What a great day"))
                return 1 - evaluation.classificationError // validation accuracy
            }
            """#,
            notes: [
                "Training blocks the calling thread for seconds to minutes: run it in a detached task, never on the main actor.",
                "Compile the written .mlmodel with MLModel.compileModel(at:) before loading it with Core ML.",
                "Create ML on iOS supports fewer model types than on macOS; check the class's availability before planning a feature.",
            ]
        ),
        "translation": ImplementationGuide(
            snippet: #"""
            import SwiftUI
            import Translation

            struct TranslateView: View {
                let text = "Where is the train station?"
                @State private var translated = ""
                @State private var configuration: TranslationSession.Configuration?

                var body: some View {
                    VStack(spacing: 12) {
                        Text(translated)
                        Button("Translate to German") {
                            configuration = .init(source: Locale.Language(identifier: "en"),
                                                  target: Locale.Language(identifier: "de"))
                        }
                    }
                    // Runs whenever the configuration changes; the system may ask to download the languages.
                    .translationTask(configuration) { session in
                        do {
                            translated = try await session.translate(text).targetText
                        } catch {
                            translated = "Translation failed: \(error.localizedDescription)"
                        }
                    }
                }
            }

            /// .installed, .supported (needs a download) or .unsupported.
            func status(from source: String, to target: String) async -> LanguageAvailability.Status {
                await LanguageAvailability().status(from: .init(identifier: source), to: .init(identifier: target))
            }
            """#,
            notes: [
                "Call configuration?.invalidate() to translate again with the same language pair.",
                "Translation runs on device once the languages are installed; the download prompt is shown by the system.",
                "Batch many strings with session.translations(from:) instead of one translate call per string.",
            ]
        ),
    ]
}
