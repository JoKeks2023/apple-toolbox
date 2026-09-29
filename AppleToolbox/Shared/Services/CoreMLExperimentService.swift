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

enum CoreMLComputeUnitsOption: String, CaseIterable, Identifiable {
    case all = "All (CPU, GPU, Neural Engine)"
    case cpuOnly = "CPU only"
    case cpuAndGPU = "CPU & GPU"
    case cpuAndNeuralEngine = "CPU & Neural Engine"
    var id: String { rawValue }
}

@MainActor
final class CoreMLExperimentService: ObservableObject {
    static let modelExtensions = ["mlmodel", "mlpackage", "mlmodelc"]
    nonisolated private static let workingFolderPrefix = "CoreMLExperiment-"

    @Published private(set) var devices: [ComputeDeviceInfo] = []
    @Published var computeUnits = CoreMLComputeUnitsOption.all {
        didSet { if oldValue != computeUnits, compiledModelURL != nil { reload() } }
    }
    @Published private(set) var summary: CoreMLModelSummary?
    @Published private(set) var output = "Import a .mlmodel, .mlpackage or compiled .mlmodelc to inspect it. No inference is run."
    @Published private(set) var isError = false
    @Published private(set) var isLoading = false
    private var loadTask: Task<Void, Never>?
    /// The compiled model inside the app's temporary directory; reused when the compute units change.
    private var compiledModelURL: URL?
    private var sourceName = ""
    private var origin = ""

    init() { refreshDevices() }

    func refreshDevices() {
        #if canImport(CoreML)
        devices = MLComputeDevice.allComputeDevices.enumerated().map { index, device in Self.describe(device, index: index) }
        #endif
    }

    func importModel(from url: URL) {
        guard !isLoading else { return }
        let ext = url.pathExtension.lowercased()
        guard Self.modelExtensions.contains(ext) else {
            setOutput("“\(url.lastPathComponent)” is not a Core ML model. Choose a .mlmodel, .mlpackage or .mlmodelc.", error: true)
            return
        }
        isLoading = true
        summary = nil
        loadTask = Task { [weak self] in await self?.compileAndLoad(url, ext: ext) }
    }

    func reportImportFailure(_ error: Error) {
        setOutput("File import error: \(error.localizedDescription)", error: true)
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        if isLoading {
            isLoading = false
            setOutput("Model loading cancelled.", error: false)
        }
    }

    private func reload() {
        guard !isLoading, let compiledModelURL else { return }
        isLoading = true
        loadTask = Task { [weak self] in await self?.load(compiledModelURL) }
    }

    private func compileAndLoad(_ source: URL, ext: String) async {
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
                origin = "Compiled from .\(ext) on device in \(Self.format(ContinuousClock.now - started))"
            }
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: compiled); return }
            compiledModelURL = compiled
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
        configuration.computeUnits = Self.mlComputeUnits(computeUnits)
        let started = ContinuousClock.now
        do {
            let model = try await MLModel.load(contentsOf: compiled, configuration: configuration)
            guard !Task.isCancelled else { return }
            summary = Self.summarize(model, fileName: sourceName, origin: origin)
            isLoading = false
            setOutput("Loaded \(sourceName) in \(Self.format(ContinuousClock.now - started)). The description below comes from MLModel.modelDescription; no prediction was run.", error: false)
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
    private static func mlComputeUnits(_ option: CoreMLComputeUnitsOption) -> MLComputeUnits {
        switch option {
        case .all: .all
        case .cpuOnly: .cpuOnly
        case .cpuAndGPU: .cpuAndGPU
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        }
    }

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

extension CoreMLExperimentService: StoppableExperiment { var isActive: Bool { isLoading } }
