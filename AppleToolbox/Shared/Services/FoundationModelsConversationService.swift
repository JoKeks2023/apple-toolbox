import Foundation
import Combine
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - Choices, transcript rows and failures

nonisolated enum FMToolset: String, CaseIterable, Identifiable, Sendable {
    case both = "Device capabilities + experiment catalog"
    case deviceCapabilities = "Device capabilities"
    case experimentCatalog = "Experiment catalog"
    case none = "No tools"
    var id: String { rawValue }

    var includesDeviceCapabilities: Bool { self == .both || self == .deviceCapabilities }
    var includesExperimentCatalog: Bool { self == .both || self == .experimentCatalog }
}

nonisolated struct FMTranscriptEntry: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case instructions = "Instructions"
        case prompt = "Prompt"
        case toolCall = "Tool call"
        case toolOutput = "Tool output"
        case response = "Response"
        case other = "Other"
    }

    let id: String
    let role: Role
    let title: String
    let text: String
}

/// The failure states the framework reports, with what they mean for the user.
nonisolated enum FMFailureKind: String, CaseIterable, Sendable {
    case contextWindowExceeded, guardrailViolation, unsupportedLanguage, assetsUnavailable, rateLimited, concurrentRequests
    case refusal, decodingFailure, unsupportedGuide, toolCallFailed, timeout, other

    var title: String {
        switch self {
        case .contextWindowExceeded: "Context window exceeded"
        case .guardrailViolation: "Guardrail violation"
        case .unsupportedLanguage: "Unsupported language or locale"
        case .assetsUnavailable: "Model assets unavailable"
        case .rateLimited: "Rate limited"
        case .concurrentRequests: "Concurrent requests"
        case .refusal: "Refusal"
        case .decodingFailure: "Decoding failure"
        case .unsupportedGuide: "Unsupported generation guide"
        case .toolCallFailed: "Tool call failed"
        case .timeout: "Timeout"
        case .other: "Generation failed"
        }
    }

    var explanation: String {
        switch self {
        case .contextWindowExceeded:
            "Instructions, tool schemas, every prompt, tool output and response of this session no longer fit into the model's context. Continue in a new session that keeps only the instructions and the last response, or start over."
        case .guardrailViolation:
            "Apple's safety guardrails flagged the prompt or the generated text. The session stays usable; rephrase the request."
        case .unsupportedLanguage:
            "The on-device model does not support the language of the prompt. Write in one of the model's supported languages."
        case .assetsUnavailable:
            "The model's assets are not available right now, e.g. while Apple Intelligence downloads or updates them."
        case .rateLimited:
            "The system is limiting requests, which happens more for apps in the background. Try again shortly."
        case .concurrentRequests:
            "A LanguageModelSession answers one request at a time; the previous response had not finished."
        case .refusal:
            "The model declined to answer. Its own explanation is shown when the framework provides one."
        case .decodingFailure:
            "The model's output could not be decoded into the requested type."
        case .unsupportedGuide:
            "A generation guide in the schema is not supported by this model."
        case .toolCallFailed:
            "One of the app's tools threw an error while the model was calling it."
        case .timeout:
            "The request took too long and was ended by the framework."
        case .other:
            "The framework returned an error that this app does not classify further."
        }
    }

    var offersCondensedSession: Bool { self == .contextWindowExceeded }
}

nonisolated struct FMFailure: Equatable, Sendable {
    let kind: FMFailureKind
    let detail: String
}

// MARK: - Pure helpers

nonisolated enum FMContextMath {
    /// Fraction of the context window used, clamped to 0…1.
    static func usage(tokens: Int, contextSize: Int) -> Double {
        guard contextSize > 0 else { return 0 }
        return min(max(Double(tokens) / Double(contextSize), 0), 1)
    }

    /// A prompt far larger than the context window (roughly 6 characters per requested token), to provoke the real overflow error.
    static func oversizedPrompt(contextSize: Int) -> String {
        let sentence = "Apple Toolbox measures how much text fits into the on-device model's context window. "
        let repeats = max(1, contextSize * 6 / sentence.count + 1)
        return "Summarize the following text in one sentence.\n" + String(repeating: sentence, count: repeats)
    }

    /// Recovery for an overflowing session (Apple's TN3193 condenses the transcript into a new session): keep the
    /// instructions and the last response. A trailing prompt is dropped, since it is usually the one that overflowed.
    static func condensed<Entry>(_ entries: [Entry], isInstructions: (Entry) -> Bool, isResponse: (Entry) -> Bool) -> [Entry] {
        var kept: [Entry] = []
        if let first = entries.first, isInstructions(first) { kept.append(first) }
        if let last = entries.last(where: isResponse) { kept.append(last) }
        return kept
    }

    /// "zh-Hans" → "zh".
    static func baseLanguageCode(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }
}

nonisolated enum FMToolFormatting {
    /// The device-capability tool's answer for one section (or "All") filtered by an optional keyword.
    static func capabilities(_ report: DeviceScanReport, section: String, keyword: String) -> String {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sections = report.sections.filter { section == "All" || $0.title.caseInsensitiveCompare(section) == .orderedSame }
        var lines: [String] = []
        for section in sections {
            let items = section.items.filter { keyword.isEmpty || $0.name.lowercased().contains(keyword) || $0.detail.lowercased().contains(keyword) }
            guard !items.isEmpty else { continue }
            lines.append("\(section.title):")
            lines += items.map { "- \($0.name): \($0.state.rawValue) (\($0.detail))" }
        }
        guard !lines.isEmpty else { return "No capability on this \(report.platform) device matches section “\(section)” and keyword “\(keyword)”." }
        return "Device platform: \(report.platform)\n" + lines.joined(separator: "\n")
    }
}

/// Keyword search over the experiment catalog, used by the catalog tool.
enum ExperimentCatalogSearch {
    static func rank(_ query: String, in experiments: [ExperimentDescriptor]) -> [ExperimentDescriptor] {
        let words = Self.words(query).filter { $0.count > 1 }
        guard !words.isEmpty else { return [] }
        let scored = experiments.map { experiment -> (ExperimentDescriptor, Int) in
            let fields = [(experiment.name, 3), (experiment.frameworks.joined(separator: " "), 2), (experiment.category.rawValue, 2), (experiment.description, 1)]
            let score = fields.reduce(0) { total, field in total + words.filter { matches($0, in: field.0) }.count * field.1 }
            return (experiment, score)
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }.map(\.0)
    }

    /// Short words ("AR", "NFC") must match a whole word; longer ones may match inside a word ("speech" in "SpeechAnalyzer").
    static func matches(_ word: String, in text: String) -> Bool {
        word.count <= 3 ? words(text).contains(word) : text.lowercased().contains(word)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func answer(_ query: String, limit: Int = 6) -> String {
        let matches = rank(query, in: ExperimentRegistry.all).prefix(limit)
        guard !matches.isEmpty else { return "No experiment in Apple Toolbox matches “\(query)”." }
        return matches.map { experiment in
            "- \(experiment.name) [\(experiment.category.rawValue)] · status on this device: \(experiment.currentStatus.title) · frameworks: \(experiment.frameworks.joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}

// MARK: - Tools

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
@Generable(description: "Which part of the device's capabilities to read")
nonisolated struct DeviceCapabilityQuery {
    @Guide(description: "The capability section", .anyOf(["Hardware", "Sensors", "Cameras & Audio", "Display", "Apple Features", "System", "All"]))
    var section: String
    @Guide(description: "Optional keyword to filter capability names, for example NFC, LiDAR or barometer; empty for everything in the section")
    var keyword: String
}

/// Reads the real capabilities of the device through the app's DeviceScanner (public APIs only, no prompts).
nonisolated struct DeviceCapabilityTool: Tool {
    let name = "lookUpDeviceCapabilities"
    let description = "Returns the real hardware, sensor, camera, display, Apple feature and system capabilities of the device this app runs on."
    let report: @Sendable (String) -> Void

    @concurrent func call(arguments: DeviceCapabilityQuery) async throws -> String {
        report("\(name)(section: \(arguments.section), keyword: \"\(arguments.keyword)\")")
        let scan = await DeviceScanner.scan()
        return FMToolFormatting.capabilities(scan, section: arguments.section, keyword: arguments.keyword)
    }
}

@Generable(description: "A search in the app's experiment catalog")
nonisolated struct ExperimentCatalogQuery {
    @Guide(description: "Keywords matching experiment names, frameworks or categories, for example NFC, speech, Wallet or sensors")
    var query: String
}

/// Searches Apple Toolbox's experiment catalog and reports each match's live status on this device.
nonisolated struct ExperimentCatalogTool: Tool {
    let name = "searchExperimentCatalog"
    let description = "Searches the Apple Toolbox catalog of experiments with Apple frameworks and returns matches with their live status on this device."
    let report: @Sendable (String) -> Void

    @concurrent func call(arguments: ExperimentCatalogQuery) async throws -> String {
        report("\(name)(query: \"\(arguments.query)\")")
        let query = arguments.query
        return await MainActor.run { ExperimentCatalogSearch.answer(query) }
    }
}

nonisolated enum FMTranscriptRenderer {
    static func render(_ transcript: Transcript) -> [FMTranscriptEntry] {
        transcript.map { render($0) }
    }

    static func render(_ entry: Transcript.Entry) -> FMTranscriptEntry {
        switch entry {
        case .instructions(let instructions):
            let tools = instructions.toolDefinitions.map(\.name)
            return FMTranscriptEntry(id: instructions.id, role: .instructions, title: tools.isEmpty ? "Instructions" : "Instructions · tools: \(tools.joined(separator: ", "))", text: text(instructions.segments))
        case .prompt(let prompt):
            return FMTranscriptEntry(id: prompt.id, role: .prompt, title: "Prompt", text: text(prompt.segments))
        case .toolCalls(let calls):
            return FMTranscriptEntry(id: calls.id, role: .toolCall, title: "Tool call", text: calls.map { "\($0.toolName) \($0.arguments.jsonString)" }.joined(separator: "\n"))
        case .toolOutput(let output):
            return FMTranscriptEntry(id: output.id, role: .toolOutput, title: "Tool output · \(output.toolName)", text: text(output.segments))
        case .response(let response):
            return FMTranscriptEntry(id: response.id, role: .response, title: "Response", text: text(response.segments))
        default:
            return FMTranscriptEntry(id: entry.id, role: .other, title: "Other entry", text: String(describing: entry))
        }
    }

    static func isInstructions(_ entry: Transcript.Entry) -> Bool {
        if case .instructions = entry { true } else { false }
    }

    static func isResponse(_ entry: Transcript.Entry) -> Bool {
        if case .response = entry { true } else { false }
    }

    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): structure.content.jsonString
            default: "[\(String(describing: segment))]"
            }
        }.joined(separator: "\n")
    }
}

nonisolated enum FMErrorClassifier {
    static func classify(_ error: Error) -> FMFailure {
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return FMFailure(kind: .toolCallFailed, detail: "\(toolError.tool.name): \(toolError.underlyingError.localizedDescription)")
        }
        if #available(iOS 27.0, macOS 27.0, *), let failure = classifyCurrent(error) { return failure }
        if let error = error as? LanguageModelSession.GenerationError {
            let kind: FMFailureKind = switch error {
            case .exceededContextWindowSize: .contextWindowExceeded
            case .assetsUnavailable: .assetsUnavailable
            case .guardrailViolation: .guardrailViolation
            case .unsupportedGuide: .unsupportedGuide
            case .unsupportedLanguageOrLocale: .unsupportedLanguage
            case .decodingFailure: .decodingFailure
            case .rateLimited: .rateLimited
            case .concurrentRequests: .concurrentRequests
            case .refusal: .refusal
            @unknown default: .other
            }
            return FMFailure(kind: kind, detail: [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap { $0 }.joined(separator: " "))
        }
        return FMFailure(kind: .other, detail: error.localizedDescription)
    }

    /// The error types introduced with iOS and macOS 27.
    @available(iOS 27.0, macOS 27.0, *)
    private static func classifyCurrent(_ error: Error) -> FMFailure? {
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded(let context):
                return FMFailure(kind: .contextWindowExceeded, detail: "\(context.tokenCount) tokens requested, the context holds \(context.contextSize). \(context.debugDescription)")
            case .guardrailViolation(let context): return FMFailure(kind: .guardrailViolation, detail: context.debugDescription)
            case .refusal(let context): return FMFailure(kind: .refusal, detail: context.debugDescription)
            case .unsupportedLanguageOrLocale(let context):
                return FMFailure(kind: .unsupportedLanguage, detail: "Language “\(context.languageCode.identifier)”: \(context.debugDescription)")
            case .rateLimited(let context): return FMFailure(kind: .rateLimited, detail: context.debugDescription)
            case .timeout(let context): return FMFailure(kind: .timeout, detail: context.debugDescription)
            case .unsupportedGenerationGuide(let context): return FMFailure(kind: .unsupportedGuide, detail: context.debugDescription)
            case .unsupportedCapability(let context): return FMFailure(kind: .other, detail: context.debugDescription)
            case .unsupportedTranscriptContent(let context): return FMFailure(kind: .other, detail: context.debugDescription)
            @unknown default: return FMFailure(kind: .other, detail: error.localizedDescription)
            }
        }
        if let error = error as? LanguageModelSession.Error {
            return FMFailure(kind: error == .concurrentRequests ? .concurrentRequests : .other, detail: error.localizedDescription)
        }
        if let error = error as? SystemLanguageModel.Error {
            return FMFailure(kind: .assetsUnavailable, detail: error.localizedDescription)
        }
        return nil
    }

    /// The model's own explanation of a refusal, when the framework offers one.
    static func refusalExplanation(_ error: Error) async -> String? {
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError, case .refusal(let refusal) = error {
            return try? await refusal.explanation.content
        }
        if let error = error as? LanguageModelSession.GenerationError, case .refusal(let refusal, _) = error {
            return try? await refusal.explanation.content
        }
        return nil
    }
}
#endif

// MARK: - Service

@MainActor
final class FoundationModelsConversationService: ObservableObject {
    static let instructions = """
    You are the assistant inside Apple Toolbox, an app that runs real experiments with Apple frameworks on this device. \
    Use the tools to answer questions about this device's capabilities and about the app's experiments; never guess capabilities. \
    Answer concisely in plain text.
    """

    @Published var toolset = FMToolset.both {
        didSet { if oldValue != toolset { resetConversation(note: "Tools changed to “\(toolset.rawValue)”; the next prompt starts a new session.") } }
    }
    @Published var prompt = "Which sensors does this device have, and which experiments in this app could I try with them?"
    @Published private(set) var entries: [FMTranscriptEntry] = []
    @Published private(set) var pendingPrompt: String?
    @Published private(set) var streamingReply = ""
    @Published private(set) var toolActivity: [String] = []
    @Published private(set) var isResponding = false
    @Published private(set) var isModelAvailable = false
    @Published private(set) var availabilityText = "—"
    @Published private(set) var contextSize: Int?
    @Published private(set) var transcriptTokens: Int?
    @Published private(set) var toolSchemaTokens: Int?
    @Published private(set) var usageText: String?
    @Published private(set) var turns = 0
    @Published private(set) var hasSession = false
    @Published private(set) var failure: FMFailure?
    @Published private(set) var output = "Ask a question; the model can call the app's tools and keeps the whole conversation in one LanguageModelSession."
    @Published private(set) var isError = false
    private var generation: Task<Void, Never>?
    /// Base language codes of `SystemLanguageModel.supportedLanguages`, read once per availability refresh.
    private var supportedLanguageCodes: Set<String> = []
    #if canImport(FoundationModels) && (os(iOS) || os(macOS))
    private var session: LanguageModelSession?
    private var tools: [any Tool] = []
    #endif

    init() { refreshAvailability() }

    var isSupported: Bool {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    func refreshAvailability() {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        let model = SystemLanguageModel.default
        isModelAvailable = model.isAvailable
        contextSize = model.contextSize
        supportedLanguageCodes = Set(model.supportedLanguages.compactMap { $0.languageCode?.identifier })
        availabilityText = switch model.availability {
        case .available: "Available"
        case .unavailable(.deviceNotEligible): "Unavailable · deviceNotEligible"
        case .unavailable(.appleIntelligenceNotEnabled): "Unavailable · appleIntelligenceNotEnabled"
        case .unavailable(.modelNotReady): "Unavailable · modelNotReady"
        case .unavailable(let reason): "Unavailable · \(reason)"
        }
        if !isModelAvailable, !isResponding { setOutput("The on-device model cannot run right now (\(availabilityText)). See the Foundation Models experiment for details.", error: true) }
        #else
        availabilityText = "Not available on \(CurrentPlatform.value.rawValue)"
        setOutput("LanguageModelSession is only available on iOS, iPadOS and macOS.", error: true)
        #endif
    }

    /// The detected prompt language and whether the on-device model supports it.
    var promptLanguageNote: String? {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS)) && canImport(NaturalLanguage)
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12, let language = NLLanguageRecognizer.dominantLanguage(for: text), language != .undetermined else { return nil }
        let code = FMContextMath.baseLanguageCode(language.rawValue)
        let supported = supportedLanguageCodes.contains(code)
        let name = Locale.current.localizedString(forIdentifier: language.rawValue) ?? language.rawValue
        return "Prompt language: \(name) · \(supported ? "supported by the model" : "not in the model's supported languages")"
        #else
        return nil
        #endif
    }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard submit(text, shown: text) else { return }
        prompt = ""
    }

    /// Sends a prompt far larger than the context window to show the real overflow error.
    func sendOversizedPrompt() {
        let text = FMContextMath.oversizedPrompt(contextSize: contextSize ?? 4_096)
        submit(text, shown: "Oversized prompt · \(text.count.formatted()) characters")
    }

    func resetConversation(note: String? = nil) {
        generation?.cancel()
        generation = nil
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        session = nil
        tools = []
        #endif
        hasSession = false
        entries = []
        pendingPrompt = nil
        streamingReply = ""
        toolActivity = []
        isResponding = false
        turns = 0
        transcriptTokens = nil
        toolSchemaTokens = nil
        usageText = nil
        failure = nil
        setOutput(note ?? "Started over; the next prompt opens a new LanguageModelSession.", error: false)
    }

    /// Continues in a new session that carries only the instructions and the last response.
    func continueInCondensedSession() {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        guard let old = session, !isResponding else { return }
        let all = Array(old.transcript)
        let kept = FMContextMath.condensed(all, isInstructions: FMTranscriptRenderer.isInstructions, isResponse: FMTranscriptRenderer.isResponse)
        let condensed = LanguageModelSession(tools: tools, transcript: Transcript(entries: kept))
        session = condensed
        failure = nil
        entries = FMTranscriptRenderer.render(condensed.transcript)
        setOutput("Continued in a new LanguageModelSession with \(kept.count) of \(all.count) transcript entries (instructions and the last response).", error: false)
        Task { [weak self] in await self?.refreshTokenCounts(condensed) }
        #endif
    }

    func stop() {
        generation?.cancel()
        generation = nil
        guard isResponding else { return }
        isResponding = false
        pendingPrompt = nil
        streamingReply = ""
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        if let session { entries = FMTranscriptRenderer.render(session.transcript) }
        #endif
        setOutput("Stopped waiting for the response.", error: false)
    }

    @discardableResult
    private func submit(_ text: String, shown: String) -> Bool {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        guard !text.isEmpty, !isResponding else { return false }
        refreshAvailability()
        guard isModelAvailable else { return false }
        let session = activeSession()
        isResponding = true
        failure = nil
        streamingReply = ""
        toolActivity = []
        pendingPrompt = shown
        setOutput("Waiting for the model; it may call tools before answering…", error: false)
        let started = ContinuousClock.now
        generation = Task { [weak self] in
            do {
                for try await snapshot in session.streamResponse(to: text) {
                    guard !Task.isCancelled else { return }
                    self?.streamingReply = snapshot.content
                }
                guard !Task.isCancelled, let self else { return }
                let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
                await self.finishTurn(session, message: "Answered in \(elapsed).")
            } catch {
                guard !Task.isCancelled, let self else { return }
                await self.failTurn(error, session: session)
            }
        }
        return true
        #else
        return false
        #endif
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    #if canImport(FoundationModels) && (os(iOS) || os(macOS))
    private func activeSession() -> LanguageModelSession {
        if let session { return session }
        let report: @Sendable (String) -> Void = { @Sendable [weak self] call in
            Task { @MainActor in self?.toolActivity.append(call) }
        }
        var tools: [any Tool] = []
        if toolset.includesDeviceCapabilities { tools.append(DeviceCapabilityTool(report: report)) }
        if toolset.includesExperimentCatalog { tools.append(ExperimentCatalogTool(report: report)) }
        let session = LanguageModelSession(tools: tools, instructions: Self.instructions)
        session.prewarm()
        self.tools = tools
        self.session = session
        hasSession = true
        return session
    }

    private func finishTurn(_ session: LanguageModelSession, message: String) async {
        turns += 1
        entries = FMTranscriptRenderer.render(session.transcript)
        pendingPrompt = nil
        streamingReply = ""
        isResponding = false
        let calls = toolActivity.count
        setOutput("\(message) \(calls == 0 ? "No tool was called." : "\(calls) tool call(s) this turn.") The session now holds \(session.transcript.count) transcript entries.", error: false)
        await refreshTokenCounts(session)
    }

    private func failTurn(_ error: Error, session: LanguageModelSession) async {
        var failure = FMErrorClassifier.classify(error)
        if failure.kind == .refusal, let explanation = await FMErrorClassifier.refusalExplanation(error) {
            failure = FMFailure(kind: .refusal, detail: failure.detail + "\nModel's explanation: " + explanation)
        }
        self.failure = failure
        entries = FMTranscriptRenderer.render(session.transcript)
        pendingPrompt = nil
        streamingReply = ""
        isResponding = false
        setOutput("\(failure.kind.title): \(failure.detail)", error: true)
        await refreshTokenCounts(session)
    }

    private func refreshTokenCounts(_ session: LanguageModelSession) async {
        let model = SystemLanguageModel.default
        transcriptTokens = try? await model.tokenCount(for: session.transcript)
        toolSchemaTokens = tools.isEmpty ? 0 : try? await model.tokenCount(for: tools)
        if #available(iOS 27.0, macOS 27.0, *) {
            let usage = session.usage
            usageText = "input \(usage.input.totalTokenCount) (cached \(usage.input.cachedTokenCount)) · output \(usage.output.totalTokenCount)"
        }
    }
    #endif
}

extension FoundationModelsConversationService: StoppableExperiment {
    var isActive: Bool { isResponding }
}
