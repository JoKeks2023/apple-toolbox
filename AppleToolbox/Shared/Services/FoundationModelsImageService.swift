import Foundation
import Combine
import CoreGraphics
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif
#if canImport(_Vision_FoundationModels) && (os(iOS) || os(macOS))
import _Vision_FoundationModels
#endif

/// Which Vision tools the session offers the model (`_Vision_FoundationModels`, iOS 27).
nonisolated enum FMVisionTool: String, CaseIterable, Identifiable, Sendable {
    case none = "No tool"
    case barcodeReader = "BarcodeReaderTool · codes"
    case ocr = "OCRTool · text"
    case both = "Both Vision tools"
    var id: String { rawValue }

    /// A question that makes the model reach for the tool.
    var suggestedQuestion: String {
        switch self {
        case .none: "Describe this image in two sentences."
        case .barcodeReader: "Read every QR code or barcode in the photo and tell me what it contains."
        case .ocr: "Transcribe the text visible in the photo."
        case .both: "List the codes and the text you can find in the photo."
        }
    }
}

/// One tool call or tool output from the session transcript.
nonisolated struct FMToolEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let text: String
}

@MainActor
final class FoundationModelsImageService: ObservableObject {
    @Published var question = FMVisionTool.none.suggestedQuestion
    @Published var tool = FMVisionTool.none {
        didSet { if FMVisionTool.allCases.map(\.suggestedQuestion).contains(question) { question = tool.suggestedQuestion } }
    }
    @Published private(set) var image: CGImage?
    @Published private(set) var imageName: String?
    @Published private(set) var status: ExperimentStatus = .unavailable
    @Published private(set) var facts: [ModelFact] = []
    @Published private(set) var execution: [AIExecutionFact] = []
    @Published private(set) var response = ""
    @Published private(set) var toolEvents: [FMToolEvent] = []
    @Published private(set) var output = ""
    @Published private(set) var isError = false
    @Published private(set) var isGenerating = false
    private var generation: Task<Void, Never>?

    static var visionToolsInSDK: Bool {
        #if canImport(_Vision_FoundationModels) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    init() { refresh() }

    var canAsk: Bool {
        status == .available && image != nil && !isGenerating && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (tool == .none || Self.visionToolsInSDK)
    }

    func refresh() {
        status = ExperimentAvailability.foundationModelsImage()
        let pcc = ProvisioningInspector.load().profile?.entitlements[AIExecutionFacts.pccEntitlement] != nil
        var imageInput: Bool?
        var facts = [ModelFact(title: "OS", value: ProcessInfo.processInfo.operatingSystemVersionString)]
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        if #available(iOS 27.0, macOS 27.0, *) {
            let model = SystemLanguageModel.default
            let capabilities = model.capabilities
            imageInput = capabilities.contains(.vision)
            facts += [
                ModelFact(title: "Model availability", value: model.isAvailable ? "Available" : "\(model.availability)"),
                ModelFact(title: "Model variant", value: model.variant.displayName),
                ModelFact(title: "Capabilities", value: Self.describe(capabilities)),
                ModelFact(title: "Context size", value: "\(model.contextSize) tokens"),
            ]
        } else {
            facts.append(ModelFact(title: "Image input", value: "Requires iOS 27 / macOS 27"))
        }
        #else
        facts.append(ModelFact(title: "Image input", value: "Not available on \(CurrentPlatform.value.rawValue)"))
        #endif
        facts.append(ModelFact(title: "Vision tools", value: Self.visionToolsInSDK ? "BarcodeReaderTool, OCRTool" : "Not in this build's SDK"))
        self.facts = facts
        execution = AIExecutionFacts.foundationModels(imageInput: imageInput, visionToolsInSDK: Self.visionToolsInSDK, pccProvisioned: pcc)
        if !isGenerating { setOutput(Self.statusMessage(status), error: status != .available) }
    }

    func setImage(data: Data, name: String) {
        Task { [weak self] in
            let decoded = await Self.decode(data)
            guard let self else { return }
            guard let decoded else { return self.setOutput("ImageIO could not decode \(name) as an image.", error: true) }
            self.image = decoded
            self.imageName = name
            self.response = ""
            self.toolEvents = []
            self.setOutput("\(name): \(decoded.width) × \(decoded.height) px (EXIF orientation applied, longest side at most 2048 px). Ask a question about it.", error: false)
        }
    }

    func reportImageFailure(_ message: String) {
        setOutput(message, error: true)
    }

    func ask() {
        refresh()
        guard canAsk, let image else { return }
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let tools = Self.tools(tool)
        isGenerating = true
        response = ""
        toolEvents = []
        setOutput("Streaming the answer from SystemLanguageModel with the photo attached\(tools.isEmpty ? "" : " and \(tools.count) Vision tool\(tools.count == 1 ? "" : "s")")…", error: false)
        generation = Task { [weak self] in
            let started = ContinuousClock.now
            let session = LanguageModelSession(model: SystemLanguageModel.default, tools: tools,
                                               instructions: "You answer questions about the attached photo, labeled \"photo\". When asked about codes or text in it, call the matching tool with that image. Answer in plain text.")
            do {
                let stream = session.streamResponse {
                    question
                    Attachment(image).label("photo")
                }
                for try await snapshot in stream {
                    guard !Task.isCancelled else { return }
                    self?.response = snapshot.content
                }
                guard !Task.isCancelled else { return }
                self?.toolEvents = Self.toolEvents(in: session.transcript)
                let calls = self?.toolEvents.filter { $0.title.hasPrefix("Call") }.count ?? 0
                self?.finish("Answered in \(Self.format(ContinuousClock.now - started)) on device. \(calls == 0 ? "The model called no tool." : "The model called \(calls) tool\(calls == 1 ? "" : "s"); see the transcript below.")", error: false)
            } catch {
                guard !Task.isCancelled else { return }
                self?.toolEvents = Self.toolEvents(in: session.transcript)
                let localized = error as? LocalizedError
                let lines = ["Generation failed: \(localized?.errorDescription ?? error.localizedDescription)", localized?.failureReason, localized?.recoverySuggestion]
                self?.finish(lines.compactMap { $0 }.joined(separator: "\n"), error: true)
            }
        }
        #endif
    }

    func stop() {
        generation?.cancel()
        generation = nil
        if isGenerating { finish("Generation stopped.", error: false) }
    }

    private func finish(_ message: String, error: Bool) {
        isGenerating = false
        generation = nil
        setOutput(message, error: error)
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    private static func statusMessage(_ status: ExperimentStatus) -> String {
        switch status {
        case .available: "The on-device model accepts images. Choose a photo and ask about it."
        case .osUnsupported: "Requires iOS 27 or macOS 27: image prompts use Transcript.ImageAttachment and Attachment, which this OS version (\(ProcessInfo.processInfo.operatingSystemVersionString)) does not have."
        case .platformUnsupported: "SystemLanguageModel is only available on iOS, iPadOS and macOS."
        case .hardwareUnsupported: "This device is not eligible for Apple Intelligence (deviceNotEligible)."
        case .regionRestricted: "Apple Intelligence does not support the current language and region (\(Locale.current.identifier)): SystemLanguageModel.supportsLocale returned false."
        default: "The on-device model cannot take image prompts right now: Apple Intelligence is off, the model is still downloading, or it reports no .vision capability (see the facts above)."
        }
    }

    private static func format(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
    }

    /// Decodes upright (EXIF orientation applied) and caps the longest side at 2048 px.
    @concurrent nonisolated private static func decode(_ data: Data) async -> CGImage? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels) && (os(iOS) || os(macOS))
    @available(iOS 27.0, macOS 27.0, *)
    private static func tools(_ choice: FMVisionTool) -> [any Tool] {
        #if canImport(_Vision_FoundationModels) && (os(iOS) || os(macOS))
        switch choice {
        case .none: return []
        case .barcodeReader: return [BarcodeReaderTool()]
        case .ocr: return [OCRTool()]
        case .both: return [BarcodeReaderTool(), OCRTool()]
        }
        #else
        return []
        #endif
    }

    @available(iOS 27.0, macOS 27.0, *)
    private static func describe(_ capabilities: LanguageModelCapabilities) -> String {
        let named: [(String, LanguageModelCapabilities.Capability)] = [("vision", .vision), ("tool calling", .toolCalling), ("guided generation", .guidedGeneration), ("reasoning", .reasoning)]
        let present = named.filter { capabilities.contains($0.1) }.map(\.0)
        return present.isEmpty ? "none reported" : present.joined(separator: ", ")
    }

    private static func toolEvents(in transcript: Transcript) -> [FMToolEvent] {
        transcript.flatMap { entry -> [FMToolEvent] in
            switch entry {
            case .toolCalls(let calls):
                return calls.map { FMToolEvent(id: $0.id, title: "Call · \($0.toolName)", text: $0.arguments.jsonString) }
            case .toolOutput(let output):
                let text = output.segments.map { segment in
                    switch segment {
                    case .text(let text): text.content
                    case .structure(let structure): structure.content.jsonString
                    default: "[\(String(describing: segment))]"
                    }
                }.joined(separator: "\n")
                return [FMToolEvent(id: output.id, title: "Output · \(output.toolName)", text: text)]
            default:
                return []
            }
        }
    }
    #endif
}

extension FoundationModelsImageService: StoppableExperiment { var isActive: Bool { isGenerating } }
