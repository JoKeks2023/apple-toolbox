import Foundation
import Combine
#if canImport(TabularData)
import TabularData
#endif
#if canImport(CreateML) && (os(iOS) || os(macOS))
import CreateML
import CoreML
#endif

// MARK: - Choices

nonisolated enum CreateMLTask: String, CaseIterable, Identifiable, Sendable {
    case textClassifier = "Text classifier"
    case tabularRegressor = "Tabular regressor"
    var id: String { rawValue }
}

nonisolated enum CreateMLTextAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case maxEnt = "Maximum entropy"
    case staticEmbedding = "Transfer learning · static embedding"
    case bertEmbedding = "Transfer learning · BERT embedding"
    var id: String { rawValue }
}

nonisolated enum CreateMLRegressorAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case linear = "Linear regression"
    case boostedTree = "Boosted tree"
    case randomForest = "Random forest"
    case decisionTree = "Decision tree"
    var id: String { rawValue }
}

nonisolated enum CreateMLValidationOption: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic split"
    case holdOut = "20 % hold-out"
    case none = "No validation"
    var id: String { rawValue }
}

// MARK: - Dataset and results

nonisolated enum CreateMLColumnKind: String, Sendable {
    case integer = "Int", decimal = "Double", text = "String", other = "Other"
    var isNumeric: Bool { self == .integer || self == .decimal }
}

nonisolated struct CreateMLColumnInfo: Identifiable, Equatable, Sendable {
    let name: String
    let kind: CreateMLColumnKind
    /// The first row's value, used to prefill prediction inputs.
    let example: String
    var id: String { name }
}

nonisolated struct CreateMLLabelCount: Identifiable, Equatable, Sendable {
    let label: String
    let count: Int
    var id: String { label }
}

nonisolated struct CreateMLDatasetInfo: Equatable, Sendable {
    let columns: [CreateMLColumnInfo]
    let rowCount: Int

    var textColumns: [CreateMLColumnInfo] { columns.filter { $0.kind == .text } }
    var numericColumns: [CreateMLColumnInfo] { columns.filter { $0.kind.isNumeric } }
}

nonisolated struct CreateMLMetricRow: Identifiable, Equatable, Sendable {
    let title: String
    let training: String
    let validation: String
    var id: String { title }
}

nonisolated struct CreateMLLabelMetric: Identifiable, Equatable, Sendable {
    let label: String
    let precision: String
    let recall: String
    var id: String { label }
}

nonisolated struct CreateMLTrainingReport: Equatable, Sendable {
    let task: CreateMLTask
    let algorithm: String
    let rows: Int
    let seconds: Double
    let metrics: [CreateMLMetricRow]
    let labelMetrics: [CreateMLLabelMetric]
    let confusions: [String]
    let modelFacts: [CreateMLMetricRow]
    let notes: [String]
}

nonisolated struct CreateMLPrediction: Identifiable, Equatable, Sendable {
    let label: String
    let confidence: Double?
    var id: String { label }
}

// MARK: - Pure helpers

nonisolated enum CreateMLFormat {
    static func accuracy(fromClassificationError error: Double) -> Double { min(max(1 - error, 0), 1) }

    static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(1))) }

    static func number(_ value: Double) -> String { value.formatted(.number.precision(.significantDigits(1...4))) }

    /// Label probabilities from `predictionWithConfidence`, most likely first.
    static func ranked(_ confidences: [String: Double]) -> [CreateMLPrediction] {
        confidences.map { CreateMLPrediction(label: $0.key, confidence: $0.value) }
            .sorted { lhs, rhs in
                let left = lhs.confidence ?? 0, right = rhs.confidence ?? 0
                return left != right ? left > right : lhs.label < rhs.label
            }
    }

    /// The first column whose lowercased name contains one of `keywords` (Create ML's metric tables have no documented column names).
    static func column(in names: [String], matching keywords: [String]) -> String? {
        names.first { name in keywords.contains { name.lowercased().contains($0) } }
    }
}

#if canImport(TabularData)
nonisolated enum CreateMLDataset {
    static let textSample = """
    text,label
    The app crashes when I open the settings screen,bug
    Tapping save does nothing and my changes are lost,bug
    The list flickers and scrolls back to the top after every refresh,bug
    Login fails with an unknown error since the last update,bug
    Images stay blank on the detail page,bug
    The widget shows yesterday's data even after reloading,bug
    Sync stops halfway and the spinner never ends,bug
    Dark mode renders white text on a white background,bug
    Please add an export to CSV,feature
    It would be great to have a dark app icon,feature
    Could you support Apple Watch complications?,feature
    I would love keyboard shortcuts on iPad,feature
    Add a way to share a report as PDF,feature
    Please let me reorder the categories,feature
    A search field in the sidebar would help a lot,feature
    Support for multiple accounts would be nice,feature
    How do I reset my password?,question
    Where can I find the privacy settings?,question
    Is there a way to use the app offline?,question
    Which devices support the Neural Engine features?,question
    How much does the pro version cost?,question
    Can I move my data to a new iPhone?,question
    What does the orange status badge mean?,question
    Does the app work on macOS too?,question
    """

    static let tabularSample = """
    size_m2,rooms,distance_km,rent_eur
    32,1,1.2,690
    38,1,3.5,640
    45,2,0.8,910
    52,2,2.4,930
    55,2,6.0,820
    60,2,1.5,1080
    64,3,4.2,1010
    68,3,0.9,1270
    72,3,3.1,1190
    75,3,7.5,1040
    80,3,2.0,1350
    85,4,5.5,1240
    90,4,1.1,1600
    95,4,3.8,1480
    100,4,8.0,1310
    110,5,2.6,1760
    120,5,4.9,1720
    130,5,1.4,2150
    140,6,6.2,1870
    150,6,3.0,2240
    """

    static func sample(for task: CreateMLTask) -> String {
        task == .textClassifier ? textSample : tabularSample
    }

    static func frame(_ csv: String, types: [String: CSVType] = [:]) throws -> DataFrame {
        try DataFrame(csvData: Data(csv.utf8), types: types)
    }

    static func inspect(_ csv: String) throws -> CreateMLDatasetInfo {
        let table = try frame(csv)
        let columns = table.columns.map { column in
            let kind: CreateMLColumnKind = switch column.wrappedElementType {
            case is Int.Type: .integer
            case is Double.Type, is Float.Type: .decimal
            case is String.Type: .text
            default: .other
            }
            let example = column.first.flatMap { $0 }.map { "\($0)" } ?? ""
            return CreateMLColumnInfo(name: column.name, kind: kind, example: example)
        }
        return CreateMLDatasetInfo(columns: columns, rowCount: table.rows.count)
    }

    static func labelCounts(_ csv: String, column: String) throws -> [CreateMLLabelCount] {
        let table = try frame(csv)
        guard table.columns.contains(where: { $0.name == column }) else { return [] }
        let labels = table[column].map { $0.map { "\($0)" } ?? "(missing)" }
        return Dictionary(grouping: labels, by: { $0 }).map { CreateMLLabelCount(label: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }
}
#endif

// MARK: - Training (Create ML is in the macOS and iOS device SDKs, not in the iOS Simulator SDK)

#if canImport(CreateML) && (os(iOS) || os(macOS))
/// The members every Create ML tabular regressor shares.
nonisolated protocol CreateMLRegressorModel: Sendable {
    var trainingMetrics: MLRegressorMetrics { get }
    var validationMetrics: MLRegressorMetrics { get }
    func predictions(from data: DataFrame) throws -> AnyColumn
    func write(to fileURL: URL, metadata: MLModelMetadata?) throws
}

nonisolated extension MLLinearRegressor: CreateMLRegressorModel {}
nonisolated extension MLBoostedTreeRegressor: CreateMLRegressorModel {}
nonisolated extension MLRandomForestRegressor: CreateMLRegressorModel {}
nonisolated extension MLDecisionTreeRegressor: CreateMLRegressorModel {}

/// Trains synchronously; callers run it on a background task. Create ML objects never leave this type except the
/// trained models, which Create ML declares `@unchecked Sendable`.
nonisolated enum CreateMLTrainer {
    static func trainTextClassifier(csv: String, textColumn: String, labelColumn: String, algorithm: CreateMLTextAlgorithm,
                                    validation: CreateMLValidationOption) throws -> (MLTextClassifier, CreateMLTrainingReport) {
        let frame = try CreateMLDataset.frame(csv, types: [textColumn: .string, labelColumn: .string])
        let started = ContinuousClock.now
        let parameters = MLTextClassifier.ModelParameters(validation: textValidation(validation), algorithm: textAlgorithm(algorithm))
        let classifier = try MLTextClassifier(trainingData: frame, textColumn: textColumn, labelColumn: labelColumn, parameters: parameters)
        let elapsed = elapsedSeconds(since: started)
        let training = classifier.trainingMetrics
        let validationMetrics = classifier.validationMetrics
        let perLabel = validationMetrics.isValid ? validationMetrics : training
        var notes = ["Per-label metrics use the \(validationMetrics.isValid ? "validation" : "training") set."]
        if !validationMetrics.isValid { notes.append("Validation metrics: \(validationMetrics.error?.localizedDescription ?? "not computed").") }
        let report = CreateMLTrainingReport(
            task: .textClassifier, algorithm: algorithm.rawValue, rows: frame.rows.count, seconds: elapsed,
            metrics: [
                CreateMLMetricRow(title: "Accuracy", training: accuracy(training), validation: accuracy(validationMetrics)),
                CreateMLMetricRow(title: "Classification error", training: training.isValid ? CreateMLFormat.percent(training.classificationError) : "—",
                                  validation: validationMetrics.isValid ? CreateMLFormat.percent(validationMetrics.classificationError) : "—"),
            ],
            labelMetrics: labelMetrics(perLabel),
            confusions: confusions(perLabel),
            modelFacts: modelFacts(size: try? modelSize { try classifier.write(to: $0, metadata: nil) }, parameters: "\(classifier.modelParameters.algorithm)"),
            notes: notes)
        return (classifier, report)
    }

    static func trainRegressor(csv: String, target: String, algorithm: CreateMLRegressorAlgorithm,
                               validation: CreateMLValidationOption) throws -> (any CreateMLRegressorModel, CreateMLTrainingReport) {
        let frame = try CreateMLDataset.frame(csv, types: [target: .double])
        let features = frame.columns.map(\.name).filter { $0 != target }
        let started = ContinuousClock.now
        let regressor: any CreateMLRegressorModel = switch algorithm {
        case .linear:
            try MLLinearRegressor(trainingData: frame, targetColumn: target, featureColumns: features,
                                  parameters: .init(validation: regressorValidation(validation, MLLinearRegressor.ModelParameters.ValidationData.self)))
        case .boostedTree:
            try MLBoostedTreeRegressor(trainingData: frame, targetColumn: target, featureColumns: features,
                                       parameters: .init(validation: regressorValidation(validation, MLBoostedTreeRegressor.ModelParameters.ValidationData.self)))
        case .randomForest:
            try MLRandomForestRegressor(trainingData: frame, targetColumn: target, featureColumns: features,
                                        parameters: .init(validation: regressorValidation(validation, MLRandomForestRegressor.ModelParameters.ValidationData.self)))
        case .decisionTree:
            try MLDecisionTreeRegressor(trainingData: frame, targetColumn: target, featureColumns: features,
                                        parameters: .init(validation: regressorValidation(validation, MLDecisionTreeRegressor.ModelParameters.ValidationData.self)))
        }
        let elapsed = elapsedSeconds(since: started)
        let training = regressor.trainingMetrics
        let validationMetrics = regressor.validationMetrics
        var notes = ["Features: \(features.joined(separator: ", ")) → \(target)."]
        if !validationMetrics.isValid { notes.append("Validation metrics: \(validationMetrics.error?.localizedDescription ?? "not computed").") }
        let report = CreateMLTrainingReport(
            task: .tabularRegressor, algorithm: algorithm.rawValue, rows: frame.rows.count, seconds: elapsed,
            metrics: [
                CreateMLMetricRow(title: "RMSE", training: training.isValid ? CreateMLFormat.number(training.rootMeanSquaredError) : "—",
                                  validation: validationMetrics.isValid ? CreateMLFormat.number(validationMetrics.rootMeanSquaredError) : "—"),
                CreateMLMetricRow(title: "Maximum error", training: training.isValid ? CreateMLFormat.number(training.maximumError) : "—",
                                  validation: validationMetrics.isValid ? CreateMLFormat.number(validationMetrics.maximumError) : "—"),
            ],
            labelMetrics: [], confusions: [],
            modelFacts: modelFacts(size: try? modelSize { try regressor.write(to: $0, metadata: nil) }, parameters: algorithm.rawValue),
            notes: notes)
        return (regressor, report)
    }

    static func classify(_ text: String, with classifier: MLTextClassifier) throws -> [CreateMLPrediction] {
        CreateMLFormat.ranked(try classifier.predictionWithConfidence(from: text))
    }

    /// Builds a one-row DataFrame with the training column types and returns the predicted target.
    static func predict(_ values: [String: String], columns: [CreateMLColumnInfo], with regressor: any CreateMLRegressorModel) throws -> Double? {
        var row = DataFrame()
        for column in columns {
            let raw = values[column.name, default: ""].trimmingCharacters(in: .whitespaces)
            switch column.kind {
            case .integer: row.append(column: Column<Int>(name: column.name, contents: [Int(raw)]))
            case .decimal: row.append(column: Column<Double>(name: column.name, contents: [Double(raw.replacingOccurrences(of: ",", with: "."))]))
            case .text, .other: row.append(column: Column<String>(name: column.name, contents: [raw]))
            }
        }
        let column = try regressor.predictions(from: row)
        return column.first.flatMap { $0 }.flatMap { ($0 as? Double) ?? ($0 as? Float).map(Double.init) ?? ($0 as? Int).map(Double.init) }
    }

    private static func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private static func textValidation(_ option: CreateMLValidationOption) -> MLTextClassifier.ModelParameters.ValidationData {
        switch option {
        case .automatic: .split(strategy: .automatic)
        case .holdOut: .split(strategy: .fixed(ratio: 0.2, seed: 7))
        case .none: .none
        }
    }

    private static func textAlgorithm(_ algorithm: CreateMLTextAlgorithm) -> MLTextClassifier.ModelAlgorithmType {
        switch algorithm {
        case .maxEnt: .maxEnt(revision: 1)
        case .staticEmbedding: .transferLearning(.staticEmbedding, revision: 1)
        case .bertEmbedding: .transferLearning(.bertEmbedding, revision: 1)
        }
    }

    /// Every regressor has its own ValidationData enum with the same cases.
    private static func regressorValidation<V: CreateMLRegressorValidation>(_ option: CreateMLValidationOption, _: V.Type) -> V {
        switch option {
        case .automatic: .split(strategy: .automatic)
        case .holdOut: .split(strategy: .fixed(ratio: 0.2, seed: 7))
        case .none: .none
        }
    }

    private static func accuracy(_ metrics: MLClassifierMetrics) -> String {
        metrics.isValid ? CreateMLFormat.percent(CreateMLFormat.accuracy(fromClassificationError: metrics.classificationError)) : "—"
    }

    private static func labelMetrics(_ metrics: MLClassifierMetrics) -> [CreateMLLabelMetric] {
        guard metrics.isValid else { return [] }
        let frame = metrics.precisionRecallDataFrame
        let names = frame.columns.map(\.name)
        guard let label = CreateMLFormat.column(in: names, matching: ["class", "label"]),
              let precision = CreateMLFormat.column(in: names, matching: ["precision"]),
              let recall = CreateMLFormat.column(in: names, matching: ["recall"]) else { return [] }
        return frame.rows.map { row in
            CreateMLLabelMetric(label: row[label].map { "\($0)" } ?? "?", precision: fraction(row[precision]), recall: fraction(row[recall]))
        }
    }

    /// Misclassifications from the confusion table, e.g. "bug → question: 2".
    private static func confusions(_ metrics: MLClassifierMetrics) -> [String] {
        guard metrics.isValid else { return [] }
        let frame = metrics.confusionDataFrame
        let names = frame.columns.map(\.name)
        guard let actual = CreateMLFormat.column(in: names, matching: ["true", "actual"]),
              let predicted = CreateMLFormat.column(in: names, matching: ["predict"]),
              let count = CreateMLFormat.column(in: names, matching: ["count"]) else { return [] }
        return frame.rows.compactMap { row in
            let from = row[actual].map { "\($0)" } ?? "?", to = row[predicted].map { "\($0)" } ?? "?"
            let number = (row[count] as? Int) ?? (row[count] as? Double).map { Int($0) } ?? 0
            return from != to && number > 0 ? "\(from) → \(to): \(number)" : nil
        }
    }

    private static func fraction(_ value: Any?) -> String {
        guard let number = (value as? Double) ?? (value as? Float).map(Double.init), number.isFinite else { return "—" }
        return CreateMLFormat.percent(number > 1 ? number / 100 : number)
    }

    private static func modelFacts(size: Int64?, parameters: String) -> [CreateMLMetricRow] {
        [
            CreateMLMetricRow(title: "Algorithm", training: parameters, validation: ""),
            CreateMLMetricRow(title: "Core ML model size", training: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—", validation: ""),
        ]
    }

    /// Writes the model as .mlmodel to a temporary file and returns its size.
    private static func modelSize(_ write: (URL) throws -> Void) throws -> Int64 {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CreateMLExperiment-\(UUID().uuidString).mlmodel")
        defer { try? FileManager.default.removeItem(at: url) }
        try write(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

nonisolated protocol CreateMLRegressorValidation {
    static func split(strategy: MLSplitStrategy) -> Self
    static var none: Self { get }
}

nonisolated extension MLLinearRegressor.ModelParameters.ValidationData: CreateMLRegressorValidation {}
nonisolated extension MLBoostedTreeRegressor.ModelParameters.ValidationData: CreateMLRegressorValidation {}
nonisolated extension MLRandomForestRegressor.ModelParameters.ValidationData: CreateMLRegressorValidation {}
nonisolated extension MLDecisionTreeRegressor.ModelParameters.ValidationData: CreateMLRegressorValidation {}
#endif

// MARK: - Service

@MainActor
final class CreateMLExperimentService: ObservableObject {
    @Published var task = CreateMLTask.textClassifier {
        didSet { if oldValue != task { loadSample() } }
    }
    @Published var textAlgorithm = CreateMLTextAlgorithm.maxEnt
    @Published var regressorAlgorithm = CreateMLRegressorAlgorithm.linear
    @Published var validation = CreateMLValidationOption.holdOut
    @Published var csv = "" {
        didSet { if oldValue != csv { inspect() } }
    }
    @Published private(set) var dataset: CreateMLDatasetInfo?
    @Published private(set) var datasetError: String?
    @Published private(set) var labelCounts: [CreateMLLabelCount] = []
    @Published var textColumn = "" { didSet { if oldValue != textColumn { refreshLabels() } } }
    @Published var labelColumn = "" { didSet { if oldValue != labelColumn { refreshLabels() } } }
    @Published var targetColumn = ""
    @Published private(set) var report: CreateMLTrainingReport?
    @Published private(set) var isTraining = false
    @Published var textInput = "The export button crashes the app"
    @Published var featureInputs: [String: String] = [:]
    @Published private(set) var predictions: [CreateMLPrediction] = []
    @Published private(set) var predictedValue: String?
    @Published private(set) var output = CreateMLExperimentService.isSupported
        ? "Edit the sample dataset or import a CSV, then train a model on this device."
        : CreateMLExperimentService.unsupportedMessage
    @Published private(set) var isError = !CreateMLExperimentService.isSupported
    /// Increments per training run so a stopped run's late result is ignored.
    private var generation = 0
    /// The feature columns and kinds the current regressor was trained with.
    private var trainedFeatures: [CreateMLColumnInfo] = []
    #if canImport(CreateML) && (os(iOS) || os(macOS))
    private var classifier: MLTextClassifier?
    private var regressor: (any CreateMLRegressorModel)?
    #endif

    static var isSupported: Bool {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    static var unsupportedMessage: String {
        #if os(iOS) && targetEnvironment(simulator)
        "CreateML.framework ships in the iOS device SDK but not in the iOS Simulator SDK, so this build contains no Create ML code. Run on an iPhone, iPad or Mac to train."
        #else
        "The Create ML framework's text and tabular trainers are not available on this platform."
        #endif
    }

    var hasTrainedModel: Bool { report != nil }

    init() { loadSample() }

    func loadSample() {
        #if canImport(TabularData)
        csv = CreateMLDataset.sample(for: task)
        #endif
        report = nil
        predictions = []
        predictedValue = nil
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        classifier = nil
        regressor = nil
        #endif
    }

    func importCSV(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return setOutput("“\(url.lastPathComponent)” is not a text file.", error: true)
            }
            csv = text
            setOutput("Imported \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))).", error: false)
        } catch {
            setOutput("Could not read the CSV: \(error.localizedDescription)", error: true)
        }
    }

    func reportImportFailure(_ error: Error) {
        setOutput("File import error: \(error.localizedDescription)", error: true)
    }

    func train() {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        guard !isTraining, let dataset else { return }
        generation += 1
        let run = generation
        let csv = csv, task = task, validation = validation
        let textAlgorithm = textAlgorithm, regressorAlgorithm = regressorAlgorithm
        let textColumn = textColumn, labelColumn = labelColumn, target = targetColumn
        isTraining = true
        report = nil
        predictions = []
        predictedValue = nil
        setOutput("Training a \(task.rawValue.lowercased()) (\(task == .textClassifier ? textAlgorithm.rawValue : regressorAlgorithm.rawValue)) on \(dataset.rowCount) rows…", error: false)
        Task { [weak self] in
            switch task {
            case .textClassifier:
                let result = await Self.detached { try CreateMLTrainer.trainTextClassifier(csv: csv, textColumn: textColumn, labelColumn: labelColumn, algorithm: textAlgorithm, validation: validation) }
                guard let self, self.generation == run else { return }
                switch result {
                case .success(let (classifier, report)):
                    self.classifier = classifier
                    self.regressor = nil
                    self.finishTraining(report)
                case .failure(let error): self.failTraining(error)
                }
            case .tabularRegressor:
                let result = await Self.detached { try CreateMLTrainer.trainRegressor(csv: csv, target: target, algorithm: regressorAlgorithm, validation: validation) }
                guard let self, self.generation == run else { return }
                switch result {
                case .success(let (regressor, report)):
                    self.regressor = regressor
                    self.classifier = nil
                    self.trainedFeatures = dataset.columns.filter { $0.name != target }
                    self.featureInputs = Dictionary(uniqueKeysWithValues: self.trainedFeatures.map { ($0.name, self.featureInputs[$0.name] ?? $0.example) })
                    self.finishTraining(report)
                case .failure(let error): self.failTraining(error)
                }
            }
        }
        #endif
    }

    /// Create ML's trainers cannot be interrupted; a stopped run keeps computing in the background and its result is discarded.
    func stop() {
        guard isTraining else { return }
        generation += 1
        isTraining = false
        setOutput("Stopped waiting. Create ML cannot interrupt a running trainer, so it finishes in the background and its result is discarded.", error: false)
    }

    func predict() {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        if let classifier {
            let text = textInput
            Task { [weak self] in
                let result = await Self.detached { try CreateMLTrainer.classify(text, with: classifier) }
                switch result {
                case .success(let predictions):
                    self?.predictions = predictions
                    self?.setOutput("predictionWithConfidence(from:) returned \(predictions.count) label probabilities.", error: false)
                case .failure(let error): self?.setOutput("Prediction failed: \(error.localizedDescription)", error: true)
                }
            }
        } else if let regressor {
            let values = featureInputs, columns = trainedFeatures
            Task { [weak self] in
                let result = await Self.detached { try CreateMLTrainer.predict(values, columns: columns, with: regressor) }
                switch result {
                case .success(let value):
                    self?.predictedValue = value.map(CreateMLFormat.number) ?? "—"
                    self?.setOutput(value == nil ? "The regressor returned no value for this row." : "predictions(from:) returned \(value.map(CreateMLFormat.number) ?? "—").", error: value == nil)
                case .failure(let error): self?.setOutput("Prediction failed: \(error.localizedDescription)", error: true)
                }
            }
        }
        #endif
    }

    var trainedFeatureColumns: [CreateMLColumnInfo] { trainedFeatures }

    private func finishTraining(_ report: CreateMLTrainingReport) {
        self.report = report
        isTraining = false
        let headline = report.metrics.first.map { "\($0.title): training \($0.training), validation \($0.validation)" } ?? ""
        setOutput("Trained on device in \(report.seconds.formatted(.number.precision(.fractionLength(2)))) s. \(headline)", error: false)
    }

    private func failTraining(_ error: Error) {
        isTraining = false
        setOutput("Create ML training failed: \(error.localizedDescription)", error: true)
    }

    private func inspect() {
        #if canImport(TabularData)
        do {
            let info = try CreateMLDataset.inspect(csv)
            dataset = info
            datasetError = nil
            if !info.textColumns.contains(where: { $0.name == textColumn }) { textColumn = info.textColumns.first { $0.name == "text" }?.name ?? info.textColumns.first?.name ?? "" }
            if !info.textColumns.contains(where: { $0.name == labelColumn }) {
                labelColumn = info.textColumns.first { $0.name == "label" }?.name ?? info.textColumns.last?.name ?? ""
            }
            if !info.numericColumns.contains(where: { $0.name == targetColumn }) { targetColumn = info.numericColumns.last?.name ?? "" }
            refreshLabels()
        } catch {
            dataset = nil
            labelCounts = []
            datasetError = "TabularData could not parse the CSV: \(error.localizedDescription)"
        }
        #endif
    }

    private func refreshLabels() {
        #if canImport(TabularData)
        labelCounts = (try? CreateMLDataset.labelCounts(csv, column: labelColumn)) ?? []
        #endif
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    /// Runs Create ML work off the main actor and hands back only Sendable values.
    @concurrent nonisolated private static func detached<T: Sendable>(_ body: @Sendable () throws -> T) async -> Result<T, Error> {
        Result { try body() }
    }
}

#if !os(watchOS)
extension CreateMLExperimentService: StoppableExperiment {
    var isActive: Bool { isTraining }
}
#endif

extension ExperimentAvailability {
    static func createML() -> ExperimentStatus {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        return .available
        #elseif os(iOS) && targetEnvironment(simulator)
        return .deviceOnly
        #else
        return .platformUnsupported
        #endif
    }
}
