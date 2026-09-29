import Foundation
import Combine
#if canImport(CoreML)
import CoreML
#endif
#if canImport(Metal)
import Metal
#endif

struct ComputeDeviceInfo: Identifiable, Equatable {
    let id: String
    let kind: String
    let detail: String
    let symbol: String
}

struct ModelFeatureInfo: Identifiable, Equatable {
    let name: String
    let type: String
    let detail: String
    var id: String { name }
}

struct CoreMLModelSummary: Equatable {
    let fileName: String
    let origin: String
    let computeUnits: String
    let facts: [ModelFact]
    let metadata: [ModelFact]
    let inputs: [ModelFeatureInfo]
    let outputs: [ModelFeatureInfo]
}

nonisolated enum CoreMLComputeUnitsOption: String, CaseIterable, Identifiable, Sendable {
    case all = "All (CPU, GPU, Neural Engine)"
    case cpuOnly = "CPU only"
    case cpuAndGPU = "CPU & GPU"
    case cpuAndNeuralEngine = "CPU & Neural Engine"
    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .all: "All"
        case .cpuOnly: "CPU"
        case .cpuAndGPU: "CPU+GPU"
        case .cpuAndNeuralEngine: "CPU+ANE"
        }
    }
}

// MARK: - Benchmark statistics (shared with the Core AI experiment)

/// Timings of repeated predictions. The first run is reported separately (it pays for lazy initialization);
/// the other figures describe the warm runs after it, or the single run when there is only one.
nonisolated struct InferenceTimingStats: Equatable, Sendable {
    let runs: Int
    let firstMilliseconds: Double
    let minMilliseconds: Double
    let medianMilliseconds: Double
    let meanMilliseconds: Double
    let maxMilliseconds: Double

    init?(milliseconds samples: [Double]) {
        guard let first = samples.first else { return nil }
        let warm = (samples.count > 1 ? Array(samples.dropFirst()) : samples).sorted()
        runs = samples.count
        firstMilliseconds = first
        minMilliseconds = warm[0]
        maxMilliseconds = warm[warm.count - 1]
        meanMilliseconds = warm.reduce(0, +) / Double(warm.count)
        let middle = warm.count / 2
        medianMilliseconds = warm.count.isMultiple(of: 2) ? (warm[middle - 1] + warm[middle]) / 2 : warm[middle]
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// "0.042 ms", "3.18 ms", "125 ms", "1.24 s".
    static func format(_ milliseconds: Double) -> String {
        if milliseconds >= 1_000 { return (milliseconds / 1_000).formatted(.number.precision(.fractionLength(2))) + " s" }
        let digits = milliseconds < 0.1 ? 3 : milliseconds < 10 ? 2 : milliseconds < 100 ? 1 : 0
        return milliseconds.formatted(.number.precision(.fractionLength(digits))) + " ms"
    }

    var summary: String {
        runs == 1 ? "1 run: \(Self.format(firstMilliseconds))"
            : "median \(Self.format(medianMilliseconds)) · mean \(Self.format(meanMilliseconds)) · \(Self.format(minMilliseconds))–\(Self.format(maxMilliseconds)) over \(runs - 1) warm runs"
    }
}

nonisolated enum InferenceIterations: Int, CaseIterable, Identifiable, Sendable {
    case one = 1, ten = 10, fifty = 50, hundred = 100
    var id: Int { rawValue }
    var title: String { rawValue == 1 ? "1 prediction" : "\(rawValue) predictions" }
}

/// Deterministic test input for tensors the user cannot type (audio windows, embeddings, raw tensors).
nonisolated enum SyntheticInput {
    /// Values in -1...1 from a 64-bit linear congruential generator, so every run and compute unit sees identical data.
    static func values(count: Int, seed: UInt64 = 0x5EED) -> [Float] {
        var state = seed
        return (0..<max(count, 0)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24) * 2 - 1
        }
    }
}

// MARK: - Prediction inputs and outputs

nonisolated enum CoreMLInputKind: Equatable, Sendable {
    case text
    case integer
    case double
    case image(width: Int, height: Int)
    case multiArray(shape: [Int], dataType: String)
    case unsupported(String)

    var summary: String {
        switch self {
        case .text: "String"
        case .integer: "Int64"
        case .double: "Double"
        case .image(let width, let height): "Image \(width) × \(height)"
        case .multiArray(let shape, let dataType): "\(dataType) [\(shape.map(String.init).joined(separator: " × "))] · synthetic values"
        case .unsupported(let type): "\(type) · not supported by this experiment"
        }
    }
}

nonisolated struct CoreMLInputField: Identifiable, Equatable, Sendable {
    let name: String
    let kind: CoreMLInputKind
    let isOptional: Bool
    var id: String { name }
}

nonisolated enum CoreMLInputValue: Equatable, Sendable {
    case text(String)
    case integer(Int64)
    case double(Double)
    case imageFile(URL)
    case synthetic
}

nonisolated enum CoreMLInputParser {
    /// Turns typed text into the value Core ML expects, or explains why it cannot.
    static func value(for kind: CoreMLInputKind, text: String) -> Result<CoreMLInputValue, CoreMLInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .text: return .success(.text(text))
        case .integer:
            guard let value = Int64(trimmed) else { return .failure(.notANumber(trimmed, "an integer")) }
            return .success(.integer(value))
        case .double:
            guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return .failure(.notANumber(trimmed, "a number")) }
            return .success(.double(value))
        case .multiArray: return .success(.synthetic)
        case .image: return .failure(.missingImage)
        case .unsupported(let type): return .failure(.unsupported(type))
        }
    }
}

nonisolated enum CoreMLInputError: Error, Equatable, LocalizedError {
    case notANumber(String, String)
    case missingImage
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notANumber(let text, let expected): "“\(text)” is not \(expected)."
        case .missingImage: "Choose an image for the image input first."
        case .unsupported(let type): "\(type) inputs cannot be entered in this experiment."
        }
    }
}

nonisolated struct CoreMLOutputValue: Identifiable, Equatable, Sendable {
    let name: String
    let value: String
    var id: String { name }
}

nonisolated enum CoreMLOutputFormat {
    /// "bug 81.2 % · feature 12.0 % · question 6.8 %", most likely first.
    static func topProbabilities(_ probabilities: [String: Double], limit: Int = 3) -> String {
        probabilities.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { "\($0.key) \($0.value.formatted(.percent.precision(.fractionLength(1))))" }
            .joined(separator: " · ")
    }

    /// "Neural Engine 41 · CPU 3", largest share first; nil when Core ML planned nothing.
    static func plannedDevices(_ counts: [String: Int]) -> String? {
        let parts = counts.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard !parts.isEmpty else { return nil }
        return parts.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }
}

nonisolated struct CoreMLBenchmarkResult: Identifiable, Equatable, Sendable {
    let units: CoreMLComputeUnitsOption
    let loadMilliseconds: Double
    let timings: InferenceTimingStats
    /// Per-operation device preference from MLComputePlan, or why there is none.
    let plannedDevices: String
    let outputs: [CoreMLOutputValue]
    var id: String { units.rawValue }
}

nonisolated struct TrainedModelFile: Identifiable, Equatable, Sendable {
    let url: URL
    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

// MARK: - Inference

#if canImport(CoreML)
/// Runs Core ML off the main actor. MLModel and feature providers are not Sendable, so they never leave these functions.
nonisolated enum CoreMLInference {
    /// Loads the compiled model with one compute-unit setting, then runs the same input `iterations` times.
    @concurrent static func benchmark(compiledModel url: URL, units: CoreMLComputeUnitsOption, inputs: [String: CoreMLInputValue],
                                      iterations: Int) async throws -> CoreMLBenchmarkResult {
        let planned = await plannedDevices(url, units: units)
        try Task.checkCancellation()
        return try run(url, units: units, inputs: inputs, iterations: iterations, planned: planned)
    }

    static func mlComputeUnits(_ option: CoreMLComputeUnitsOption) -> MLComputeUnits {
        switch option {
        case .all: .all
        case .cpuOnly: .cpuOnly
        case .cpuAndGPU: .cpuAndGPU
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        }
    }

    static func inputFields(_ description: MLModelDescription) -> [CoreMLInputField] {
        description.inputDescriptionsByName.values.map { feature in
            let kind: CoreMLInputKind = switch feature.type {
            case .string: .text
            case .int64: .integer
            case .double: .double
            case .image:
                .image(width: feature.imageConstraint?.pixelsWide ?? 0, height: feature.imageConstraint?.pixelsHigh ?? 0)
            case .multiArray:
                .multiArray(shape: feature.multiArrayConstraint?.shape.map(\.intValue) ?? [], dataType: feature.multiArrayConstraint.map { dataTypeName($0.dataType) } ?? "?")
            case .dictionary: .unsupported("Dictionary")
            case .sequence: .unsupported("Sequence")
            case .state: .unsupported("State")
            case .invalid: .unsupported("Invalid")
            @unknown default: .unsupported("MLFeatureType(\(feature.type.rawValue))")
            }
            return CoreMLInputField(name: feature.name, kind: kind, isOptional: feature.isOptional)
        }
        .sorted { $0.name < $1.name }
    }

    static func dataTypeName(_ type: MLMultiArrayDataType) -> String {
        switch type {
        case .double: "Float64"
        case .float32: "Float32"
        case .float16: "Float16"
        case .int32: "Int32"
        case .int8: "Int8"
        @unknown default: "MLMultiArrayDataType(\(type.rawValue))"
        }
    }

    /// Synchronous on purpose: in an async context Swift would pick MLModel's async prediction, which adds scheduling to every timing.
    private static func run(_ url: URL, units: CoreMLComputeUnitsOption, inputs: [String: CoreMLInputValue], iterations: Int,
                            planned: String) throws -> CoreMLBenchmarkResult {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = mlComputeUnits(units)
        let loadStart = ContinuousClock.now
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let loadTime = InferenceTimingStats.milliseconds(ContinuousClock.now - loadStart)
        let provider = try featureProvider(for: model.modelDescription, inputs: inputs)
        var samples: [Double] = []
        var last: (any MLFeatureProvider)?
        for _ in 0..<max(iterations, 1) {
            try Task.checkCancellation()
            let start = ContinuousClock.now
            last = try model.prediction(from: provider)
            samples.append(InferenceTimingStats.milliseconds(ContinuousClock.now - start))
        }
        guard let timings = InferenceTimingStats(milliseconds: samples), let last else { throw CancellationError() }
        return CoreMLBenchmarkResult(units: units, loadMilliseconds: loadTime, timings: timings, plannedDevices: planned, outputs: describe(last))
    }

    private static func featureProvider(for description: MLModelDescription, inputs: [String: CoreMLInputValue]) throws -> any MLFeatureProvider {
        var features: [String: MLFeatureValue] = [:]
        for (name, feature) in description.inputDescriptionsByName {
            switch inputs[name] {
            case .text(let text)?: features[name] = MLFeatureValue(string: text)
            case .integer(let value)?: features[name] = MLFeatureValue(int64: value)
            case .double(let value)?: features[name] = MLFeatureValue(double: value)
            case .imageFile(let imageURL)?:
                guard let constraint = feature.imageConstraint else { throw CoreMLInputError.unsupported("Image") }
                features[name] = try MLFeatureValue(imageAt: imageURL, constraint: constraint, options: nil)
            case .synthetic?:
                guard let constraint = feature.multiArrayConstraint else { throw CoreMLInputError.unsupported("MultiArray") }
                features[name] = MLFeatureValue(multiArray: try syntheticArray(constraint))
            case nil:
                if !feature.isOptional { throw CoreMLInputError.unsupported("Input “\(name)”") }
            }
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private static func syntheticArray(_ constraint: MLMultiArrayConstraint) throws -> MLMultiArray {
        let shape = constraint.shape.isEmpty ? [NSNumber(value: 1)] : constraint.shape.map { $0.intValue > 0 ? $0 : NSNumber(value: 1) }
        let array = try MLMultiArray(shape: shape, dataType: constraint.dataType)
        let values = SyntheticInput.values(count: array.count)
        switch constraint.dataType {
        case .float32:
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
                for index in 0..<min(buffer.count, values.count) { buffer[index] = values[index] }
            }
        case .double:
            array.withUnsafeMutableBufferPointer(ofType: Double.self) { buffer, _ in
                for index in 0..<min(buffer.count, values.count) { buffer[index] = Double(values[index]) }
            }
        default:
            for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
        }
        return array
    }

    private static func describe(_ provider: any MLFeatureProvider) -> [CoreMLOutputValue] {
        provider.featureNames.sorted().compactMap { name in
            provider.featureValue(for: name).map { CoreMLOutputValue(name: name, value: describe($0)) }
        }
    }

    private static func describe(_ value: MLFeatureValue) -> String {
        switch value.type {
        case .string: return value.stringValue
        case .int64: return "\(value.int64Value)"
        case .double: return value.doubleValue.formatted(.number.precision(.significantDigits(1...6)))
        case .dictionary:
            var probabilities: [String: Double] = [:]
            for (key, number) in value.dictionaryValue { probabilities["\(key.base)"] = number.doubleValue }
            return CoreMLOutputFormat.topProbabilities(probabilities)
        case .multiArray:
            guard let array = value.multiArrayValue else { return "MultiArray" }
            let shown = (0..<min(array.count, 5)).map { array[$0].doubleValue.formatted(.number.precision(.significantDigits(1...4))) }
            return "\(dataTypeName(array.dataType)) [\(array.shape.map(\.stringValue).joined(separator: " × "))] · \(shown.joined(separator: ", "))\(array.count > 5 ? ", …" : "")"
        case .image: return "Image"
        case .sequence: return "Sequence of \(value.sequenceValue.map { $0.type == .string ? $0.stringValues.count : $0.int64Values.count } ?? 0)"
        case .state: return "State"
        case .invalid: return "Invalid"
        @unknown default: return "MLFeatureType(\(value.type.rawValue))"
        }
    }

    /// Which device Core ML prefers for each layer or operation, counted per device (MLComputePlan, iOS 17.4+).
    private static func plannedDevices(_ url: URL, units: CoreMLComputeUnitsOption) async -> String {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = mlComputeUnits(units)
        do {
            let plan = try await MLComputePlan.load(contentsOf: url, configuration: configuration)
            var counts: [String: Int] = [:]
            func visitBlock(_ block: MLModelStructure.Program.Block) {
                for operation in block.operations {
                    if let usage = plan.deviceUsage(for: operation) { counts[deviceName(usage.preferred), default: 0] += 1 }
                    operation.blocks.forEach(visitBlock)
                }
            }
            func visit(_ structure: MLModelStructure) {
                switch structure {
                case .neuralNetwork(let network):
                    for layer in network.layers {
                        if let usage = plan.deviceUsage(for: layer) { counts[deviceName(usage.preferred), default: 0] += 1 }
                    }
                case .program(let program): program.functions.values.forEach { visitBlock($0.block) }
                case .pipeline(let pipeline): pipeline.subModels.forEach(visit)
                case .unsupported: break
                @unknown default: break
                }
            }
            visit(plan.modelStructure)
            return CoreMLOutputFormat.plannedDevices(counts).map { "Preferred device per operation: \($0)" }
                ?? "MLComputePlan reports no per-operation plan for this model type (tree ensembles, GLMs and feature-print pipelines run where Core ML decides)."
        } catch {
            return "MLComputePlan could not be loaded: \(error.localizedDescription)"
        }
    }

    private static func deviceName(_ device: MLComputeDevice) -> String {
        switch device {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .neuralEngine: "Neural Engine"
        @unknown default: "Other"
        }
    }
}
#endif

@MainActor
final class CoreMLExperimentService: ObservableObject {
    static let modelExtensions = ["mlmodel", "mlpackage", "mlmodelc"]
    nonisolated private static let workingFolderPrefix = "CoreMLExperiment-"

    @Published private(set) var devices: [ComputeDeviceInfo] = []
    @Published var computeUnits = CoreMLComputeUnitsOption.all {
        didSet { if oldValue != computeUnits, compiledModelURL != nil { reload() } }
    }
    @Published private(set) var summary: CoreMLModelSummary?
    @Published private(set) var output = "Load a model trained on this device with Create ML, or import a .mlmodel, .mlpackage or compiled .mlmodelc, then run predictions."
    @Published private(set) var isError = false
    @Published private(set) var isLoading = false
    /// Models the Create ML experiment saved in Application Support › Trained Models, newest first.
    @Published private(set) var trainedModels: [TrainedModelFile] = []
    @Published var selectedTrainedModel = ""
    @Published private(set) var inputFields: [CoreMLInputField] = []
    @Published var inputTexts: [String: String] = [:]
    @Published private(set) var inputImageName: String?
    @Published var iterations = InferenceIterations.ten
    /// One row per compute-unit setting, in the order of `CoreMLComputeUnitsOption.allCases`.
    @Published private(set) var results: [CoreMLBenchmarkResult] = []
    @Published private(set) var isPredicting = false
    private var loadTask: Task<Void, Never>?
    private var predictTask: Task<Void, Never>?
    private var inputImageURL: URL?
    /// The compiled model inside the app's temporary directory; reused when the compute units change.
    private var compiledModelURL: URL?
    private var sourceName = ""
    private var origin = ""

    init() {
        refreshDevices()
        refreshTrainedModels()
    }

    func refreshTrainedModels() {
        trainedModels = CreateMLModelStore.savedModels().map(TrainedModelFile.init)
        if !trainedModels.contains(where: { $0.id == selectedTrainedModel }) { selectedTrainedModel = trainedModels.first?.id ?? "" }
    }

    func loadTrainedModel() {
        guard !isLoading, !isPredicting, let file = trainedModels.first(where: { $0.id == selectedTrainedModel }) else { return }
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            refreshTrainedModels()
            return setOutput("\(file.url.lastPathComponent) no longer exists.", error: true)
        }
        isLoading = true
        summary = nil
        loadTask = Task { [weak self] in await self?.compileAndLoad(file.url, ext: "mlmodel", trainedOnDevice: true) }
    }

    /// Why predictions cannot run right now, or nil when they can.
    var predictionBlocker: String? {
        guard summary != nil, compiledModelURL != nil else { return "Load a model first." }
        if case .failure(let error) = predictionInputs() { return error.localizedDescription }
        return nil
    }

    func setInputImage(data: Data, fileExtension: String, name: String) {
        Task { [weak self] in
            let result = await Self.storeInput { url in try data.write(to: url) }
            self?.finishInputImage(result, name: name, fileExtension: fileExtension)
        }
    }

    func setInputImage(fileURL: URL) {
        Task { [weak self] in
            let result = await Self.storeInput { url in
                let scoped = fileURL.startAccessingSecurityScopedResource()
                defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: fileURL, to: url)
            }
            self?.finishInputImage(result, name: fileURL.lastPathComponent, fileExtension: fileURL.pathExtension)
        }
    }

    /// Runs `iterations` predictions with the selected compute units, or with every setting in turn.
    func runPredictions(allUnits: Bool) {
        guard !isLoading, !isPredicting, let compiledModelURL else { return }
        let inputs: [String: CoreMLInputValue]
        switch predictionInputs() {
        case .success(let values): inputs = values
        case .failure(let error): return setOutput(error.localizedDescription, error: true)
        }
        let units = allUnits ? CoreMLComputeUnitsOption.allCases : [computeUnits]
        let count = iterations.rawValue
        isPredicting = true
        setOutput("Running \(count) prediction\(count == 1 ? "" : "s") per setting with MLModel.prediction(from:)…", error: false)
        predictTask = Task { [weak self] in
            var failures: [String] = []
            for option in units {
                guard !Task.isCancelled else { break }
                do {
                    let result = try await CoreMLInference.benchmark(compiledModel: compiledModelURL, units: option, inputs: inputs, iterations: count)
                    self?.store(result)
                } catch is CancellationError {
                    break
                } catch {
                    failures.append("\(option.rawValue): \(error.localizedDescription)")
                }
            }
            self?.finishPredictions(failures: failures, cancelled: Task.isCancelled)
        }
    }

    func refreshDevices() {
        #if canImport(CoreML)
        devices = MLComputeDevice.allComputeDevices.enumerated().map { index, device in Self.describe(device, index: index) }
        #endif
    }

    func importModel(from url: URL) {
        guard !isLoading, !isPredicting else { return }
        let ext = url.pathExtension.lowercased()
        guard Self.modelExtensions.contains(ext) else {
            setOutput("“\(url.lastPathComponent)” is not a Core ML model. Choose a .mlmodel, .mlpackage or .mlmodelc.", error: true)
            return
        }
        isLoading = true
        summary = nil
        loadTask = Task { [weak self] in await self?.compileAndLoad(url, ext: ext, trainedOnDevice: false) }
    }

    func reportImportFailure(_ error: Error) {
        setOutput("File import error: \(error.localizedDescription)", error: true)
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        predictTask?.cancel()
        predictTask = nil
        if isLoading {
            isLoading = false
            setOutput("Model loading cancelled.", error: false)
        }
        if isPredicting {
            isPredicting = false
            setOutput("Predictions stopped.", error: false)
        }
    }

    private func store(_ result: CoreMLBenchmarkResult) {
        results.removeAll { $0.units == result.units }
        results.append(result)
        results.sort { lhs, rhs in
            (CoreMLComputeUnitsOption.allCases.firstIndex(of: lhs.units) ?? 0) < (CoreMLComputeUnitsOption.allCases.firstIndex(of: rhs.units) ?? 0)
        }
    }

    private func finishPredictions(failures: [String], cancelled: Bool) {
        guard isPredicting else { return }
        isPredicting = false
        predictTask = nil
        if !failures.isEmpty {
            setOutput("Core ML prediction failed:\n" + failures.joined(separator: "\n"), error: true)
        } else if !cancelled {
            let fastest = results.min { $0.timings.medianMilliseconds < $1.timings.medianMilliseconds }
            setOutput("Predictions finished. Fastest median: \(fastest.map { "\($0.units.rawValue), \(InferenceTimingStats.format($0.timings.medianMilliseconds))" } ?? "—"). Core ML may run layers on another unit than requested when a unit cannot execute them; the planned devices show its choice.", error: false)
        }
    }

    private func predictionInputs() -> Result<[String: CoreMLInputValue], CoreMLInputError> {
        var values: [String: CoreMLInputValue] = [:]
        for field in inputFields {
            if case .image = field.kind {
                if let inputImageURL { values[field.name] = .imageFile(inputImageURL) } else if !field.isOptional { return .failure(.missingImage) }
                continue
            }
            switch CoreMLInputParser.value(for: field.kind, text: inputTexts[field.name, default: ""]) {
            case .success(let value): values[field.name] = value
            case .failure(let error): if !field.isOptional { return .failure(error) }
            }
        }
        return .success(values)
    }

    private func finishInputImage(_ result: Result<URL, Error>, name: String, fileExtension: String) {
        switch result {
        case .success(let url):
            if let old = inputImageURL { try? FileManager.default.removeItem(at: old) }
            inputImageURL = url
            inputImageName = name
            setOutput("Image input set to \(name). Core ML scales and converts it to the model's image constraint (MLFeatureValue(imageAt:constraint:)).", error: false)
        case .failure(let error):
            setOutput("The image could not be stored: \(error.localizedDescription)", error: true)
        }
    }

    /// Stores an input file in the temporary directory; the security-scoped original may become unreadable later.
    @concurrent nonisolated private static func storeInput(_ write: @Sendable (URL) throws -> Void) async -> Result<URL, Error> {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CoreMLInput-\(UUID().uuidString)")
        return Result { try write(url); return url }
    }

    private func reload() {
        guard !isLoading, let compiledModelURL else { return }
        isLoading = true
        loadTask = Task { [weak self] in await self?.load(compiledModelURL) }
    }

    private func compileAndLoad(_ source: URL, ext: String, trainedOnDevice: Bool) async {
        #if canImport(CoreML)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            removeWorkingCopy()
            let started = ContinuousClock.now
            let compiled: URL
            if ext == "mlmodelc" {
                setOutput("Copying \(source.lastPathComponent) into the app's temporary directory…", error: false)
                compiled = try await Self.copyToTemporaryDirectory(source)
                origin = "Precompiled .mlmodelc (no compilation needed)"
            } else {
                setOutput("Compiling \(source.lastPathComponent) on device with MLModel.compileModel(at:)…", error: false)
                compiled = try await MLModel.compileModel(at: source)
                origin = (trainedOnDevice ? "Trained on this device with Create ML · " : "") + "Compiled from .\(ext) on device in \(Self.format(ContinuousClock.now - started))"
            }
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: compiled); return }
            compiledModelURL = compiled
            results = []
            sourceName = source.lastPathComponent
            await load(compiled)
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            setOutput("Core ML could not read the model: \(error.localizedDescription)", error: true)
        }
        #endif
    }

    private func load(_ compiled: URL) async {
        #if canImport(CoreML)
        setOutput("Loading the compiled model with \(computeUnits.rawValue)…", error: false)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = CoreMLInference.mlComputeUnits(computeUnits)
        let started = ContinuousClock.now
        do {
            let model = try await MLModel.load(contentsOf: compiled, configuration: configuration)
            guard !Task.isCancelled else { return }
            summary = Self.summarize(model, fileName: sourceName, origin: origin)
            let fields = CoreMLInference.inputFields(model.modelDescription)
            if fields != inputFields {
                inputFields = fields
                inputTexts = Dictionary(uniqueKeysWithValues: fields.compactMap { field in
                    switch field.kind {
                    case .text: (field.name, inputTexts[field.name] ?? (field.name == "text" ? "The export button crashes the app" : ""))
                    case .integer, .double: (field.name, inputTexts[field.name] ?? "1")
                    default: nil
                    }
                })
            }
            isLoading = false
            setOutput("Loaded \(sourceName) with \(computeUnits.rawValue) in \(Self.format(ContinuousClock.now - started)). Fill in the inputs below and run predictions.", error: false)
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            summary = nil
            setOutput("Core ML could not load the model: \(error.localizedDescription)", error: true)
        }
        #endif
    }

    private func removeWorkingCopy() {
        guard let compiledModelURL else { return }
        let folder = compiledModelURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folder.lastPathComponent.hasPrefix(Self.workingFolderPrefix) ? folder : compiledModelURL)
        self.compiledModelURL = nil
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    /// Copies off the main actor; the copy stays readable after the security-scoped access ends.
    private static func copyToTemporaryDirectory(_ source: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(workingFolderPrefix + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }.value
    }

    private static func format(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated))
    }

    #if canImport(CoreML)

    private static func name(of units: MLComputeUnits) -> String {
        switch units {
        case .all: CoreMLComputeUnitsOption.all.rawValue
        case .cpuOnly: CoreMLComputeUnitsOption.cpuOnly.rawValue
        case .cpuAndGPU: CoreMLComputeUnitsOption.cpuAndGPU.rawValue
        case .cpuAndNeuralEngine: CoreMLComputeUnitsOption.cpuAndNeuralEngine.rawValue
        @unknown default: "MLComputeUnits(\(units.rawValue))"
        }
    }

    private static func describe(_ device: MLComputeDevice, index: Int) -> ComputeDeviceInfo {
        switch device {
        case .cpu:
            return ComputeDeviceInfo(id: "cpu-\(index)", kind: "CPU", detail: "\(ProcessInfo.processInfo.activeProcessorCount) active cores", symbol: "cpu")
        case .gpu(let gpu):
            var detail = "Metal device not reported"
            #if canImport(Metal)
            if let metal = gpu.metalDevice {
                let workingSet = ByteCountFormatter.string(fromByteCount: Int64(metal.recommendedMaxWorkingSetSize), countStyle: .memory)
                detail = "\(metal.name) · unified memory: \(metal.hasUnifiedMemory ? "yes" : "no") · working set: \(workingSet)"
            }
            #endif
            return ComputeDeviceInfo(id: "gpu-\(index)", kind: "GPU", detail: detail, symbol: "cube.transparent")
        case .neuralEngine(let engine):
            return ComputeDeviceInfo(id: "ane-\(index)", kind: "Neural Engine", detail: "\(engine.totalCoreCount) cores", symbol: "brain")
        @unknown default:
            return ComputeDeviceInfo(id: "device-\(index)", kind: "Other", detail: device.description, symbol: "questionmark.square")
        }
    }

    private static func summarize(_ model: MLModel, fileName: String, origin: String) -> CoreMLModelSummary {
        let description = model.modelDescription
        let metadata = description.metadata
        func text(_ key: MLModelMetadataKey) -> String {
            guard let value = metadata[key] as? String, !value.isEmpty else { return "Not set" }
            return value
        }
        var metadataFacts = [
            ModelFact(title: "Author", value: text(.author)),
            ModelFact(title: "Version", value: text(.versionString)),
            ModelFact(title: "Description", value: text(.description)),
            ModelFact(title: "License", value: text(.license)),
        ]
        if let creator = metadata[.creatorDefinedKey] as? [String: String], !creator.isEmpty {
            metadataFacts += creator.sorted { $0.key < $1.key }.map { ModelFact(title: $0.key, value: $0.value) }
        }
        var facts = [ModelFact(title: "Updatable", value: description.isUpdatable ? "Yes" : "No")]
        if let predicted = description.predictedFeatureName { facts.append(ModelFact(title: "Predicted feature", value: predicted)) }
        if let labels = description.classLabels { facts.append(ModelFact(title: "Class labels", value: "\(labels.count)")) }
        if !description.stateDescriptionsByName.isEmpty { facts.append(ModelFact(title: "States", value: description.stateDescriptionsByName.keys.sorted().joined(separator: ", "))) }
        return CoreMLModelSummary(
            fileName: fileName,
            origin: origin,
            computeUnits: name(of: model.configuration.computeUnits),
            facts: facts,
            metadata: metadataFacts,
            inputs: description.inputDescriptionsByName.values.map(feature).sorted { $0.name < $1.name },
            outputs: description.outputDescriptionsByName.values.map(feature).sorted { $0.name < $1.name })
    }

    private static func feature(_ feature: MLFeatureDescription) -> ModelFeatureInfo {
        let optional = feature.isOptional ? " · optional" : ""
        switch feature.type {
        case .multiArray:
            guard let constraint = feature.multiArrayConstraint else { return ModelFeatureInfo(name: feature.name, type: "MultiArray", detail: optional) }
            var detail = "\(dataType(constraint.dataType)) [\(constraint.shape.map(\.stringValue).joined(separator: " × "))]"
            switch constraint.shapeConstraint.type {
            case .enumerated: detail += " · \(constraint.shapeConstraint.enumeratedShapes.count) allowed shapes"
            case .range: detail += " · flexible ranges"
            default: break
            }
            return ModelFeatureInfo(name: feature.name, type: "MultiArray", detail: detail + optional)
        case .image:
            guard let constraint = feature.imageConstraint else { return ModelFeatureInfo(name: feature.name, type: "Image", detail: optional) }
            var detail = "\(constraint.pixelsWide) × \(constraint.pixelsHigh) · \(fourCharacterCode(constraint.pixelFormatType))"
            if constraint.sizeConstraint.type != .unspecified { detail += " · flexible size" }
            return ModelFeatureInfo(name: feature.name, type: "Image", detail: detail + optional)
        case .dictionary:
            let key = feature.dictionaryConstraint.map { typeName($0.keyType) } ?? "?"
            return ModelFeatureInfo(name: feature.name, type: "Dictionary", detail: "\(key) → Double" + optional)
        case .sequence:
            let element = feature.sequenceConstraint.map { typeName($0.valueDescription.type) } ?? "?"
            return ModelFeatureInfo(name: feature.name, type: "Sequence", detail: "of \(element)" + optional)
        case .state:
            let detail = feature.stateConstraint.map { "\(dataType($0.dataType)) [\($0.bufferShape.map(String.init).joined(separator: " × "))]" } ?? ""
            return ModelFeatureInfo(name: feature.name, type: "State", detail: detail + optional)
        default:
            return ModelFeatureInfo(name: feature.name, type: typeName(feature.type), detail: "Scalar" + optional)
        }
    }

    private static func typeName(_ type: MLFeatureType) -> String {
        switch type {
        case .int64: "Int64"
        case .double: "Double"
        case .string: "String"
        case .image: "Image"
        case .multiArray: "MultiArray"
        case .dictionary: "Dictionary"
        case .sequence: "Sequence"
        case .state: "State"
        case .invalid: "Invalid"
        @unknown default: "MLFeatureType(\(type.rawValue))"
        }
    }

    private static func dataType(_ type: MLMultiArrayDataType) -> String {
        switch type {
        case .double: "Float64"
        case .float32: "Float32"
        case .float16: "Float16"
        case .int32: "Int32"
        case .int8: "Int8"
        @unknown default: "MLMultiArrayDataType(\(type.rawValue))"
        }
    }

    private static func fourCharacterCode(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return "pixel format \(code)" }
        return String(decoding: bytes, as: UTF8.self)
    }
    #endif
}

extension CoreMLExperimentService: StoppableExperiment { var isActive: Bool { isLoading || isPredicting } }
