import Foundation
import Combine
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif

struct ModelFact: Identifiable, Equatable {
    let title: String
    let value: String
    var id: String { title }
}

/// The typed fields of the guided-generation result, mirrored so the run view compiles on every platform.
struct GeneratedExperimentIdea: Equatable {
    let title: String
    let framework: String
    let difficulty: String
    let steps: [String]
}

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
@Generable(description: "A small hands-on experiment for an app that explores Apple developer frameworks")
nonisolated struct ToolboxExperimentIdea {
    @Guide(description: "A short, descriptive title")
    var title: String
    @Guide(description: "The Apple framework the experiment is built on", .anyOf(["Core ML", "Vision", "Foundation Models", "Sound Analysis", "Translation", "Natural Language", "Speech", "Core Motion", "Core Location", "ARKit"]))
    var framework: String
    var difficulty: Difficulty
    @Guide(description: "Concrete build steps, each one sentence", .count(3))
    var steps: [String]

    @Generable
    enum Difficulty: String { case beginner, intermediate, advanced }
}
#endif

@MainActor
final class FoundationModelsExperimentService: ObservableObject {
    @Published var prompt = "In two sentences: what can an app do with an on-device language model?"
    @Published private(set) var facts: [ModelFact] = []
    @Published private(set) var isModelAvailable = false
    @Published private(set) var response = ""
    @Published private(set) var idea: GeneratedExperimentIdea?
    @Published private(set) var output = "Foundation Models is ready."
    @Published private(set) var isError = false
    @Published private(set) var isGenerating = false
    private var generation: Task<Void, Never>?

    init() { refreshAvailability() }

    func refreshAvailability() {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        let model = SystemLanguageModel.default
        let (state, reason) = Self.describe(model.availability)
        isModelAvailable = model.isAvailable
        let locale = Locale.current.identifier
        facts = [
            ModelFact(title: "Availability", value: state),
            ModelFact(title: "Reason", value: reason),
            ModelFact(title: "Execution", value: "On device (SystemLanguageModel.default)"),
            ModelFact(title: "Current locale", value: model.supportsLocale() ? "\(locale) · supported" : "\(locale) · not supported"),
            ModelFact(title: "Supported languages", value: "\(model.supportedLanguages.count)"),
            ModelFact(title: "Context size", value: "\(model.contextSize) tokens"),
        ]
        if !isGenerating { setOutput(isModelAvailable ? "The on-device model is ready. Ask a question or generate a structured result." : "The model cannot run right now: \(reason)", error: !isModelAvailable) }
        #else
        isModelAvailable = false
        facts = [ModelFact(title: "Availability", value: "Not available on \(CurrentPlatform.value.rawValue)")]
        setOutput("SystemLanguageModel is only available on iOS, iPadOS and macOS.", error: true)
        #endif
    }

    /// Streams a plain-text reply from a fresh session.
    func ask() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, beginGeneration() else { return }
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        response = ""
        setOutput("Streaming the response…", error: false)
        generation = Task { [weak self] in
            let started = ContinuousClock.now
            do {
                let session = LanguageModelSession(instructions: "You are a concise assistant inside a developer toolbox app. Answer in plain text.")
                for try await snapshot in session.streamResponse(to: text) {
                    guard !Task.isCancelled else { return }
                    self?.response = snapshot.content
                }
                guard !Task.isCancelled else { return }
                self?.endGeneration("Response streamed in \(Self.format(ContinuousClock.now - started)) from a fresh LanguageModelSession.", error: false)
            } catch {
                guard !Task.isCancelled else { return }
                self?.endGeneration(error)
            }
        }
        #endif
    }

    /// Guided generation: the model must produce a value of the @Generable type, so the fields arrive typed.
    func generateIdea() {
        guard beginGeneration() else { return }
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        idea = nil
        setOutput("Generating a ToolboxExperimentIdea…", error: false)
        let topic = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        generation = Task { [weak self] in
            let started = ContinuousClock.now
            do {
                let session = LanguageModelSession(instructions: "You suggest small, realistic experiments that use public Apple frameworks.")
                let result = try await session.respond(to: "Suggest one experiment idea. Context from the user: \(topic.isEmpty ? "none" : topic)", generating: ToolboxExperimentIdea.self)
                guard !Task.isCancelled else { return }
                let value = result.content
                self?.idea = GeneratedExperimentIdea(title: value.title, framework: value.framework, difficulty: value.difficulty.rawValue, steps: value.steps)
                self?.endGeneration("Typed result generated in \(Self.format(ContinuousClock.now - started)).\nRaw content: \(result.rawContent.jsonString)", error: false)
            } catch {
                guard !Task.isCancelled else { return }
                self?.endGeneration(error)
            }
        }
        #endif
    }

    /// Cancelled tasks return without touching state, so a new generation cannot be ended by an old one.
    func stop() {
        generation?.cancel()
        generation = nil
        if isGenerating { endGeneration("Generation stopped.", error: false) }
    }

    private func beginGeneration() -> Bool {
        guard !isGenerating else { return false }
        refreshAvailability()
        guard isModelAvailable else { return false }
        isGenerating = true
        return true
    }

    private func endGeneration(_ message: String, error: Bool) {
        guard isGenerating else { return }
        isGenerating = false
        generation = nil
        setOutput(message, error: error)
    }

    private func endGeneration(_ error: Error) {
        let localized = error as? LocalizedError
        let lines = ["Generation failed: \(localized?.errorDescription ?? error.localizedDescription)", localized?.failureReason, localized?.recoverySuggestion]
        endGeneration(lines.compactMap { $0 }.joined(separator: "\n"), error: true)
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    private static func format(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
    }

    #if canImport(FoundationModels) && (os(iOS) || os(macOS))
    private static func describe(_ availability: SystemLanguageModel.Availability) -> (state: String, reason: String) {
        switch availability {
        case .available:
            return ("Available", "The on-device model is ready.")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return ("Unavailable", "deviceNotEligible · this device cannot run Apple Intelligence.")
            case .appleIntelligenceNotEnabled: return ("Unavailable", "appleIntelligenceNotEnabled · Apple Intelligence is turned off in Settings.")
            case .modelNotReady: return ("Unavailable", "modelNotReady · the model is still downloading or being prepared.")
            @unknown default: return ("Unavailable", "\(reason)")
            }
        }
    }
    #endif
}

extension FoundationModelsExperimentService: StoppableExperiment { var isActive: Bool { isGenerating } }
