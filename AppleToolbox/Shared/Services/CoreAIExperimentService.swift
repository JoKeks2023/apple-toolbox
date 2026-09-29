import Foundation
import Combine
#if canImport(CoreAI) && (os(iOS) || os(macOS))
import CoreAI
#endif

/// The compute preference passed to Core AI's specialization (SpecializationOptions).
nonisolated enum CoreAIComputePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Default (Core AI decides)"
    case cpuOnly = "CPU only"
    case preferGPU = "Prefer GPU"
    case preferNeuralEngine = "Prefer Neural Engine"
    var id: String { rawValue }
}

nonisolated struct CoreAIValueInfo: Identifiable, Equatable, Sendable {
    let name: String
    let summary: String
    var id: String { name }
}

nonisolated struct CoreAIFunctionInfo: Identifiable, Equatable, Sendable {
    let name: String
    let inputs: [CoreAIValueInfo]
    let outputs: [CoreAIValueInfo]
    let states: [String]
    /// Why this experiment cannot feed the function, or nil when every input is an NDArray it can fill.
    let blocker: String?
    var id: String { name }
}

nonisolated struct CoreAIRunResult: Identifiable, Equatable, Sendable {
    let function: String
    let preference: CoreAIComputePreference
    let timings: InferenceTimingStats
    let outputs: [CoreMLOutputValue]
    var id: String { "\(function)|\(preference.rawValue)" }
}

/// Pure helpers for Core AI shapes and values, testable without the framework.
nonisolated enum CoreAIShapes {
    /// Dynamic dimensions (reported as zero or negative) are resolved to 1 so a synthetic input can be built.
    static func concreteShape(_ shape: [Int]) -> [Int] {
        shape.isEmpty ? [1] : shape.map { $0 > 0 ? $0 : 1 }
    }

    static func describe(shape: [Int]) -> String {
        "[" + shape.map { $0 > 0 ? String($0) : "?" }.joined(separator: " × ") + "]"
    }

    /// "Float32 [1 × 10] · 0.12, -0.5, …" for the first values of an output.
    static func describe(scalarType: String, shape: [Int], firstValues: [Double], total: Int) -> String {
        let values = firstValues.map { $0.formatted(.number.precision(.significantDigits(1...4))) }.joined(separator: ", ")
        return "\(scalarType) \(describe(shape: shape))" + (values.isEmpty ? "" : " · \(values)\(total > firstValues.count ? ", …" : "")")
    }
}

#if canImport(CoreAI) && (os(iOS) || os(macOS))
/// Core AI calls. AIModel, InferenceFunction and NDArray are Sendable; Outputs and InferenceValue are non-copyable and
/// never leave these functions.
@available(iOS 27.0, macOS 27.0, *)
nonisolated enum CoreAIEngine {
    static func options(_ preference: CoreAIComputePreference) -> SpecializationOptions {
        switch preference {
        case .automatic: .default
        case .cpuOnly: .cpuOnly
        case .preferGPU: SpecializationOptions(preferredComputeUnitKind: .gpu)
        case .preferNeuralEngine: SpecializationOptions(preferredComputeUnitKind: .neuralEngine)
        }
    }

    static func name(_ kind: ComputeUnitKind) -> String {
        switch kind {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .neuralEngine: "Neural Engine"
        @unknown default: "\(kind)"
        }
    }

    static func names(_ kinds: Set<ComputeUnitKind>) -> String {
        kinds.isEmpty ? "none" : kinds.map(name).sorted().joined(separator: ", ")
    }

    static func scalarName(_ type: NDArray.ScalarType) -> String {
        String(describing: type).capitalized
    }

    /// Reads the asset without specializing it: metadata and, with statistics, the operation mix.
    @concurrent static func inspect(_ url: URL) async throws -> [ModelFact.Row] {
        guard AIModelAsset.isValid(at: url) else { throw CoreAIExperimentError.notAnAsset(url.lastPathComponent) }
        let asset = try AIModelAsset(contentsOf: url)
        let metadata = asset.metadata
        var rows: [ModelFact.Row] = [
            ("Author", metadata.author.isEmpty ? "Not set" : metadata.author),
            ("Description", metadata.description.isEmpty ? "Not set" : metadata.description),
            ("License", metadata.license.isEmpty ? "Not set" : metadata.license),
        ]
        if let created = metadata.creationDate { rows.append(("Created", created.formatted(date: .abbreviated, time: .shortened))) }
        if let summary = try asset.summary(includingStatistics: true) {
            rows.append(("Functions", summary.functions.map(\.name).joined(separator: ", ")))
            if !summary.computeTypes.isEmpty { rows.append(("Compute types", summary.computeTypes.joined(separator: ", "))) }
            if !summary.storageTypes.isEmpty { rows.append(("Weight storage", summary.storageTypes.map { "\($0.typeName) ×\($0.count)" }.joined(separator: ", "))) }
            let operations = summary.operationDistribution.sorted { $0.count > $1.count }
            if !operations.isEmpty {
                rows.append(("Operations", operations.prefix(8).map { "\($0.operationName) ×\($0.count)" }.joined(separator: ", ") + (operations.count > 8 ? ", …" : "")))
            }
        }
        return rows
    }

    /// Specializes (compiles for this device) or reuses the cached specialization, and describes the functions.
    @concurrent static func load(_ url: URL, preference: CoreAIComputePreference) async throws -> (model: AIModel, facts: [ModelFact.Row], functions: [CoreAIFunctionInfo]) {
        let options = options(preference)
        let cached = (try? AIModelCache.default.model(for: url, options: options)) != nil
        let started = ContinuousClock.now
        let model = try await AIModel(contentsOf: url, options: options)
        let elapsed = InferenceTimingStats.milliseconds(ContinuousClock.now - started)
        let facts: [ModelFact.Row] = [
            ("Specialization", "\(InferenceTimingStats.format(elapsed)) · \(cached ? "reused from AIModelCache" : "compiled for this device and cached")"),
            ("Allowed compute units", names(options.allowedComputeUnitKinds)),
            ("Preferred compute unit", options.preferredComputeUnitKind.map(name) ?? "None (Core AI decides)"),
        ]
        let functions = model.functionNames.sorted().compactMap { name in model.functionDescriptor(for: name).map { describe($0) } }
        return (model, facts, functions)
    }

    /// Runs one function `iterations` times with deterministic synthetic NDArray inputs.
    @concurrent static func run(_ model: AIModel, function name: String, iterations: Int) async throws -> (InferenceTimingStats, [CoreMLOutputValue]) {
        guard let descriptor = model.functionDescriptor(for: name), let function = try model.loadFunction(named: name) else {
            throw CoreAIExperimentError.missingFunction(name)
        }
        var inputs: [String: NDArray] = [:]
        for input in descriptor.inputNames {
            guard case .ndArray(let array)? = descriptor.inputDescriptor(of: input) else { throw CoreAIExperimentError.unsupportedInput(input) }
            inputs[input] = try synthetic(array)
        }
        var samples: [Double] = []
        var described: [CoreMLOutputValue] = []
        for index in 0..<max(iterations, 1) {
            try Task.checkCancellation()
            let start = ContinuousClock.now
            var outputs = try await function.run(inputs: inputs)
            samples.append(InferenceTimingStats.milliseconds(ContinuousClock.now - start))
            guard index == max(iterations, 1) - 1 else { continue }
            for outputName in Array(outputs.names).sorted() {
                guard let value = outputs.remove(outputName) else { continue }
                if value.kind == .image {
                    described.append(CoreMLOutputValue(name: outputName, value: "Image (pixel buffer)"))
                } else if let array = value.ndArray {
                    described.append(CoreMLOutputValue(name: outputName, value: describe(array)))
                }
            }
        }
        guard let timings = InferenceTimingStats(milliseconds: samples) else { throw CancellationError() }
        return (timings, described)
    }

    private static func describe(_ descriptor: InferenceFunctionDescriptor) -> CoreAIFunctionInfo {
        var blocker: String?
        let inputs = descriptor.inputNames.map { name -> CoreAIValueInfo in
            let summary = describe(descriptor.inputDescriptor(of: name))
            if case .ndArray(let array)? = descriptor.inputDescriptor(of: name) {
                if !supportsSynthetic(array.scalarType) { blocker = "Input “\(name)” is \(scalarName(array.scalarType)); this experiment fills Float and Int inputs only." }
            } else {
                blocker = "Input “\(name)” is not an NDArray; image inputs need a CVPixelBuffer, which this experiment does not build."
            }
            return CoreAIValueInfo(name: name, summary: summary)
        }
        let outputs = descriptor.outputNames.map { CoreAIValueInfo(name: $0, summary: describe(descriptor.outputDescriptor(of: $0))) }
        return CoreAIFunctionInfo(name: descriptor.name, inputs: inputs, outputs: outputs, states: descriptor.stateNames, blocker: blocker)
    }

    private static func describe(_ descriptor: InferenceValue.Descriptor?) -> String {
        switch descriptor {
        case .ndArray(let array)?:
            "\(scalarName(array.scalarType)) \(CoreAIShapes.describe(shape: array.shape))\(array.hasDynamicShape ? " · dynamic" : "")"
        case .image(let image)?:
            "Image \(image.width) × \(image.height)"
        case nil:
            "Unknown"
        case .some:
            "Other value kind"
        }
    }

    private static func supportsSynthetic(_ type: NDArray.ScalarType) -> Bool {
        switch type {
        case .float32, .float64, .int32, .int8, .int16, .int64, .uint8: true
        #if arch(arm64)
        case .float16: true
        #endif
        default: false
        }
    }

    private static func synthetic(_ descriptor: NDArrayDescriptor) throws -> NDArray {
        let shape = CoreAIShapes.concreteShape(descriptor.hasDynamicShape ? descriptor.resolvingDynamicDimensions(CoreAIShapes.concreteShape(descriptor.shape)).shape : descriptor.shape)
        let values = SyntheticInput.values(count: shape.reduce(1, *))
        switch descriptor.scalarType {
        case .float32: return NDArray(scalars: values, shape: shape)
        case .float64: return NDArray(scalars: values.map(Double.init), shape: shape)
        case .int32: return NDArray(scalars: values.map { Int32($0 * 100) }, shape: shape)
        case .int16: return NDArray(scalars: values.map { Int16($0 * 100) }, shape: shape)
        case .int8: return NDArray(scalars: values.map { Int8($0 * 100) }, shape: shape)
        case .int64: return NDArray(scalars: values.map { Int64($0 * 100) }, shape: shape)
        case .uint8: return NDArray(scalars: values.map { UInt8(($0 + 1) * 127) }, shape: shape)
        #if arch(arm64)
        case .float16: return NDArray(scalars: values.map(Float16.init), shape: shape)
        #endif
        default: throw CoreAIExperimentError.unsupportedInput(scalarName(descriptor.scalarType))
        }
    }

    private static func describe(_ array: NDArray) -> String {
        let total = array.shape.reduce(1, *)
        let first: [Double]
        switch array.scalarType {
        case .float32: first = firstValues(array, as: Float.self) { Double($0) }
        case .float64: first = firstValues(array, as: Double.self) { $0 }
        case .int32: first = firstValues(array, as: Int32.self) { Double($0) }
        case .int64: first = firstValues(array, as: Int64.self) { Double($0) }
        #if arch(arm64)
        case .float16: first = firstValues(array, as: Float16.self) { Double($0) }
        #endif
        default: first = []
        }
        return CoreAIShapes.describe(scalarType: scalarName(array.scalarType), shape: array.shape, firstValues: first, total: total)
    }

    private static func firstValues<T: BitwiseCopyable>(_ array: NDArray, as type: T.Type, _ convert: (T) -> Double) -> [Double] {
        let view = array.view(as: T.self)
        guard let span = view.contiguousElements else { return [] }
        return (0..<min(span.count, 5)).map { convert(span[$0]) }
    }
}
#endif

nonisolated enum CoreAIExperimentError: Error, LocalizedError {
    case notAnAsset(String)
    case missingFunction(String)
    case unsupportedInput(String)

    var errorDescription: String? {
        switch self {
        case .notAnAsset(let name): "AIModelAsset.isValid(at:) is false for “\(name)”: it is not a Core AI model asset (.aimodel)."
        case .missingFunction(let name): "The model has no inference function named “\(name)”."
        case .unsupportedInput(let name): "Input “\(name)” cannot be filled with synthetic NDArray data."
        }
    }
}

extension ModelFact {
    /// A (title, value) pair built off the main actor and turned into a ModelFact on it.
    typealias Row = (title: String, value: String)
}

@MainActor
final class CoreAIExperimentService: ObservableObject {
    static let modelExtension = "aimodel"

    @Published private(set) var status: ExperimentStatus = .unavailable
    @Published private(set) var deviceFacts: [ModelFact] = []
    @Published var preference = CoreAIComputePreference.automatic {
        didSet { if oldValue != preference, modelURL != nil { reload() } }
    }
    @Published private(set) var modelName: String?
    @Published private(set) var assetFacts: [ModelFact] = []
    @Published private(set) var loadFacts: [ModelFact] = []
    @Published private(set) var functions: [CoreAIFunctionInfo] = []
    @Published var selectedFunction = ""
    @Published var iterations = InferenceIterations.ten
    @Published private(set) var results: [CoreAIRunResult] = []
    @Published private(set) var output = ""
    @Published private(set) var isError = false
    @Published private(set) var isBusy = false
    private var work: Task<Void, Never>?
    /// The app's copy of the imported .aimodel package.
    private var modelURL: URL?
    #if canImport(CoreAI) && (os(iOS) || os(macOS))
    /// Type-erased so the stored property needs no availability annotation; holds an `AIModel` on iOS / macOS 27.
    private var model: (any Sendable)?
    #endif

    init() { refresh() }

    var selectedFunctionInfo: CoreAIFunctionInfo? { functions.first { $0.name == selectedFunction } }

    func refresh() {
        status = ExperimentAvailability.coreAI()
        var facts = [ModelFact(title: "OS", value: ProcessInfo.processInfo.operatingSystemVersionString)]
        #if canImport(CoreAI) && (os(iOS) || os(macOS))
        if #available(iOS 27.0, macOS 27.0, *) {
            facts += [
                ModelFact(title: "Available compute units", value: CoreAIEngine.names(ComputeUnitKind.availableKinds)),
                ModelFact(title: "Device architecture", value: AIModel.deviceArchitectureName),
            ]
        }
        #endif
        deviceFacts = facts
        if !isBusy, modelURL == nil { setOutput(Self.statusMessage(status), error: status != .available) }
    }

    func importModel(from url: URL) {
        guard !isBusy else { return }
        #if canImport(CoreAI) && (os(iOS) || os(macOS))
        guard #available(iOS 27.0, macOS 27.0, *) else { return setOutput(Self.statusMessage(.osUnsupported), error: true) }
        isBusy = true
        results = []
        functions = []
        assetFacts = []
        loadFacts = []
        setOutput("Copying \(url.lastPathComponent) and reading it with AIModelAsset…", error: false)
        work = Task { [weak self] in
            do {
                let copy = try await Self.copyToWorkingFolder(url)
                self?.replaceModel(copy)
                let rows = try await CoreAIEngine.inspect(copy)
                self?.assetFacts = rows.map { ModelFact(title: $0.title, value: $0.value) }
                await self?.specialize(copy)
            } catch {
                self?.fail("Core AI could not read the model: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func reportImportFailure(_ error: Error) {
        setOutput("File import error: \(error.localizedDescription)", error: true)
    }

    func run() {
        #if canImport(CoreAI) && (os(iOS) || os(macOS))
        guard #available(iOS 27.0, macOS 27.0, *), !isBusy, let model = model as? AIModel, let info = selectedFunctionInfo else { return }
        if let blocker = info.blocker { return setOutput(blocker, error: true) }
        let name = info.name, count = iterations.rawValue, preference = preference
        isBusy = true
        setOutput("Running “\(name)” \(count) time\(count == 1 ? "" : "s") with InferenceFunction.run(inputs:)…", error: false)
        work = Task { [weak self] in
            do {
                let (timings, outputs) = try await CoreAIEngine.run(model, function: name, iterations: count)
                guard let self else { return }
                self.results.removeAll { $0.function == name && $0.preference == preference }
                self.results.append(CoreAIRunResult(function: name, preference: preference, timings: timings, outputs: outputs))
                self.isBusy = false
                self.setOutput("“\(name)” ran \(timings.runs) time\(timings.runs == 1 ? "" : "s"): first \(InferenceTimingStats.format(timings.firstMilliseconds)), \(timings.summary). Inputs are synthetic values, so the outputs show only that inference ran.", error: false)
            } catch is CancellationError {
                return
            } catch {
                self?.fail("Inference failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// Deletes this model's specializations from AIModelCache, so the next load compiles again.
    func clearCache() {
        #if canImport(CoreAI) && (os(iOS) || os(macOS))
        guard #available(iOS 27.0, macOS 27.0, *), let modelURL else { return }
        do {
            try AIModelCache.default.deleteEntries(for: modelURL)
            setOutput("Deleted the cached specializations of \(modelName ?? "the model") (AIModelCache.deleteEntries(for:)). Reload to see a fresh compile time.", error: false)
        } catch {
            setOutput("AIModelCache could not delete the entries: \(error.localizedDescription)", error: true)
        }
        #endif
    }

    func stop() {
        work?.cancel()
        work = nil
        if isBusy {
            isBusy = false
            setOutput("Stopped.", error: false)
        }
    }

    private func reload() {
        guard !isBusy, let modelURL else { return }
        isBusy = true
        work = Task { [weak self] in await self?.specialize(modelURL) }
    }

    private func specialize(_ url: URL) async {
        #if canImport(CoreAI) && (os(iOS) || os(macOS))
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let preference = preference
        setOutput("Specializing \(url.lastPathComponent) with \(preference.rawValue) (AIModel(contentsOf:options:))…", error: false)
        do {
            let loaded = try await CoreAIEngine.load(url, preference: preference)
            guard !Task.isCancelled else { return }
            model = loaded.model
            loadFacts = loaded.facts.map { ModelFact(title: $0.title, value: $0.value) }
            functions = loaded.functions
            if !functions.contains(where: { $0.name == selectedFunction }) { selectedFunction = functions.first?.name ?? "" }
            isBusy = false
            setOutput("Loaded \(functions.count) inference function\(functions.count == 1 ? "" : "s"): \(functions.map(\.name).joined(separator: ", ")).", error: false)
        } catch {
            guard !Task.isCancelled else { return }
            model = nil
            functions = []
            fail("Core AI could not specialize the model: \(error.localizedDescription)")
        }
        #endif
    }

    private func replaceModel(_ url: URL) {
        if let modelURL { try? FileManager.default.removeItem(at: modelURL.deletingLastPathComponent()) }
        modelURL = url
        modelName = url.lastPathComponent
    }

    private func fail(_ message: String) {
        isBusy = false
        setOutput(message, error: true)
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    private static func statusMessage(_ status: ExperimentStatus) -> String {
        switch status {
        case .available: "Core AI is available. Import a .aimodel package (compiled with Xcode's aimodelc); Apple Toolbox bundles no Core AI model."
        case .osUnsupported: "Requires iOS 27 or macOS 27: CoreAI.framework (AIModel, InferenceFunction, NDArray) does not exist in \(ProcessInfo.processInfo.operatingSystemVersionString)."
        case .deviceOnly: "CoreAI.framework is in the iOS 27 device SDK but not in the iOS Simulator SDK, so this build contains no Core AI code. Run on an iPhone, iPad or Mac."
        case .hardwareUnsupported: "ComputeUnitKind.availableKinds is empty on this device."
        default: "Core AI is only available on iPhone, iPad and Mac."
        }
    }

    /// Copies off the main actor; the copy stays readable after the security-scoped access ends.
    @concurrent nonisolated private static func copyToWorkingFolder(_ source: URL) async throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CoreAIExperiment-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

extension CoreAIExperimentService: StoppableExperiment { var isActive: Bool { isBusy } }
