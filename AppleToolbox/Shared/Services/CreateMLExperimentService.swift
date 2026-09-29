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
    case imageClassifier = "Image classifier"
    case soundClassifier = "Sound classifier"
    var id: String { rawValue }

    /// Image and sound classifiers train from files grouped by label instead of a CSV table.
    var usesLabeledFiles: Bool { self == .imageClassifier || self == .soundClassifier }

    /// The noun for one training sample of a file-based task.
    var sampleNoun: String { self == .soundClassifier ? "sound" : "image" }

    /// The file name stem of an exported model, e.g. "ImageClassifier".
    var fileStem: String { rawValue.capitalized.replacingOccurrences(of: " ", with: "") }
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
    /// The trained model as written to the Trained Models folder, or nil when writing failed.
    let modelURL: URL?
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

// MARK: - Labeled file samples (image and sound classifiers)

nonisolated struct CreateMLSample: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The app's own copy of the file, so it stays readable after security-scoped access ends.
    let url: URL
    /// The original file name, shown in the list.
    let name: String
}

nonisolated struct CreateMLSampleGroup: Identifiable, Equatable, Sendable {
    let label: String
    var samples: [CreateMLSample]
    var id: String { label }
}

nonisolated enum CreateMLLabelError: Error, Equatable, LocalizedError {
    case empty
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .empty: "Enter a label name."
        case .duplicate(let label): "The label “\(label)” already exists."
        }
    }
}

/// Training samples grouped by label, in the order the labels were added. Create ML reads them as
/// `DataSource.filesByLabel`.
nonisolated struct CreateMLSampleSet: Equatable, Sendable {
    private(set) var groups: [CreateMLSampleGroup] = []

    var labels: [String] { groups.map(\.label) }
    var sampleCount: Int { groups.reduce(0) { $0 + $1.samples.count } }
    var isEmpty: Bool { groups.isEmpty }

    /// Trims the name and collapses inner whitespace, so "  red   apple " becomes "red apple".
    static func normalized(_ label: String) -> String {
        label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Adds an empty label; labels are unique regardless of case.
    @discardableResult
    mutating func addLabel(_ raw: String) throws(CreateMLLabelError) -> String {
        let label = Self.normalized(raw)
        guard !label.isEmpty else { throw .empty }
        if let existing = groups.first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) { throw .duplicate(existing.label) }
        groups.append(CreateMLSampleGroup(label: label, samples: []))
        return label
    }

    /// Removes a label and returns its samples so the caller can delete the files.
    mutating func removeLabel(_ label: String) -> [CreateMLSample] {
        guard let index = groups.firstIndex(where: { $0.label == label }) else { return [] }
        return groups.remove(at: index).samples
    }

    /// Appends samples to an existing label; unknown labels are ignored.
    mutating func add(_ samples: [CreateMLSample], to label: String) {
        guard let index = groups.firstIndex(where: { $0.label == label }) else { return }
        groups[index].samples += samples
    }

    mutating func removeSample(id: UUID) -> CreateMLSample? {
        for index in groups.indices {
            if let position = groups[index].samples.firstIndex(where: { $0.id == id }) {
                return groups[index].samples.remove(at: position)
            }
        }
        return nil
    }

    /// The training data for Create ML; labels without samples are left out.
    var filesByLabel: [String: [URL]] {
        Dictionary(uniqueKeysWithValues: groups.filter { !$0.samples.isEmpty }.map { ($0.label, $0.samples.map(\.url)) })
    }

    /// Nil when training can start, otherwise what is still missing.
    func readiness(noun: String, minimumLabels: Int = 2, minimumPerLabel: Int = 2) -> String? {
        let filled = groups.filter { !$0.samples.isEmpty }
        if filled.count < minimumLabels {
            return "Add at least \(minimumLabels) labels with \(noun)s (\(filled.count) so far)."
        }
        let short = groups.filter { $0.samples.count < minimumPerLabel }.map(\.label)
        if !short.isEmpty {
            return "Every label needs at least \(minimumPerLabel) \(noun)s: \(short.joined(separator: ", "))."
        }
        return nil
    }
}

/// Where trained models are kept: Application Support › Trained Models. The Core ML experiment lists this folder.
nonisolated enum CreateMLModelStore {
    static let folderName = "Trained Models"
    static let keptModels = 10

    static var directory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    /// E.g. "ImageClassifier-20260929-143012.mlmodel" (UTC, so names sort by time).
    static func fileName(for task: CreateMLTask, date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "\(task.fileStem)-\(stamp).mlmodel"
    }

    /// The saved .mlmodel files, newest first.
    static func savedModels() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension == "mlmodel" }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    /// Writes a model through `write` and keeps only the newest `keptModels` files.
    static func save(_ task: CreateMLTask, write: (URL) throws -> Void) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: task, date: Date()))
        try write(url)
        for old in savedModels().dropFirst(keptModels) { try? FileManager.default.removeItem(at: old) }
        return url
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
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

    /// The CSV sample of a table-based task (image and sound classifiers use labeled files instead).
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
        let saved = save(.textClassifier, algorithm: algorithm.rawValue) { try classifier.write(to: $0, metadata: $1) }
        let report = CreateMLTrainingReport(
            task: .textClassifier, algorithm: algorithm.rawValue, rows: frame.rows.count, seconds: elapsed,
            metrics: [
                CreateMLMetricRow(title: "Accuracy", training: accuracy(training), validation: accuracy(validationMetrics)),
                CreateMLMetricRow(title: "Classification error", training: training.isValid ? CreateMLFormat.percent(training.classificationError) : "—",
                                  validation: validationMetrics.isValid ? CreateMLFormat.percent(validationMetrics.classificationError) : "—"),
            ],
            labelMetrics: labelMetrics(perLabel),
            confusions: confusions(perLabel),
            modelFacts: modelFacts(url: saved.url, parameters: "\(classifier.modelParameters.algorithm)"),
            notes: notes + saved.notes,
            modelURL: saved.url)
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
        let saved = save(.tabularRegressor, algorithm: algorithm.rawValue) { try regressor.write(to: $0, metadata: $1) }
        let report = CreateMLTrainingReport(
            task: .tabularRegressor, algorithm: algorithm.rawValue, rows: frame.rows.count, seconds: elapsed,
            metrics: [
                CreateMLMetricRow(title: "RMSE", training: training.isValid ? CreateMLFormat.number(training.rootMeanSquaredError) : "—",
                                  validation: validationMetrics.isValid ? CreateMLFormat.number(validationMetrics.rootMeanSquaredError) : "—"),
                CreateMLMetricRow(title: "Maximum error", training: training.isValid ? CreateMLFormat.number(training.maximumError) : "—",
                                  validation: validationMetrics.isValid ? CreateMLFormat.number(validationMetrics.maximumError) : "—"),
            ],
            labelMetrics: [], confusions: [],
            modelFacts: modelFacts(url: saved.url, parameters: algorithm.rawValue),
            notes: notes + saved.notes,
            modelURL: saved.url)
        return (regressor, report)
    }

    static func trainImageClassifier(filesByLabel: [String: [URL]], validation: CreateMLValidationOption) throws -> (MLImageClassifier, CreateMLTrainingReport) {
        let started = ContinuousClock.now
        let parameters = MLImageClassifier.ModelParameters(validation: imageValidation(validation), augmentation: [])
        let classifier = try MLImageClassifier(trainingData: .filesByLabel(filesByLabel), parameters: parameters)
        let algorithm = "\(classifier.modelParameters.algorithm)"
        let saved = save(.imageClassifier, algorithm: algorithm) { try classifier.write(to: $0, metadata: $1) }
        let report = classifierReport(task: .imageClassifier, algorithm: algorithm, filesByLabel: filesByLabel, seconds: elapsedSeconds(since: started),
                                      training: classifier.trainingMetrics, validation: classifier.validationMetrics, saved: saved)
        return (classifier, report)
    }

    static func trainSoundClassifier(filesByLabel: [String: [URL]], validation: CreateMLValidationOption) throws -> (MLSoundClassifier, CreateMLTrainingReport) {
        let started = ContinuousClock.now
        var parameters = MLSoundClassifier.ModelParameters()
        parameters.validation = soundValidation(validation)
        let classifier = try MLSoundClassifier(trainingData: .filesByLabel(filesByLabel), parameters: parameters)
        let algorithm = "\(classifier.modelParameters.algorithm)"
        let saved = save(.soundClassifier, algorithm: algorithm) { try classifier.write(to: $0, metadata: $1) }
        let report = classifierReport(task: .soundClassifier, algorithm: algorithm, filesByLabel: filesByLabel, seconds: elapsedSeconds(since: started),
                                      training: classifier.trainingMetrics, validation: classifier.validationMetrics, saved: saved)
        return (classifier, report)
    }

    /// Create ML's image classifier returns only the most likely label; the Core ML experiment shows the probabilities.
    static func classify(imageAt url: URL, with classifier: MLImageClassifier) throws -> [String] {
        [try classifier.prediction(from: url)]
    }

    static func classify(soundAt url: URL, with classifier: MLSoundClassifier) throws -> [String] {
        try classifier.predictions(from: [url])
    }

    private static func classifierReport(task: CreateMLTask, algorithm: String, filesByLabel: [String: [URL]], seconds: Double,
                                         training: MLClassifierMetrics, validation: MLClassifierMetrics,
                                         saved: (url: URL?, notes: [String])) -> CreateMLTrainingReport {
        let perLabel = validation.isValid ? validation : training
        var notes = ["\(filesByLabel.count) labels: " + filesByLabel.keys.sorted().map { "\($0) ×\(filesByLabel[$0]?.count ?? 0)" }.joined(separator: ", ") + ".",
                     "Per-label metrics use the \(validation.isValid ? "validation" : "training") set."]
        if !validation.isValid { notes.append("Validation metrics: \(validation.error?.localizedDescription ?? "not computed").") }
        return CreateMLTrainingReport(
            task: task, algorithm: algorithm, rows: filesByLabel.values.reduce(0) { $0 + $1.count }, seconds: seconds,
            metrics: [
                CreateMLMetricRow(title: "Accuracy", training: accuracy(training), validation: accuracy(validation)),
                CreateMLMetricRow(title: "Classification error", training: training.isValid ? CreateMLFormat.percent(training.classificationError) : "—",
                                  validation: validation.isValid ? CreateMLFormat.percent(validation.classificationError) : "—"),
            ],
            labelMetrics: labelMetrics(perLabel),
            confusions: confusions(perLabel),
            modelFacts: modelFacts(url: saved.url, parameters: algorithm),
            notes: notes + saved.notes,
            modelURL: saved.url)
    }

    /// Writes the model to the Trained Models folder; a failed write is reported as a note, not as a training failure.
    private static func save(_ task: CreateMLTask, algorithm: String, write: (URL, MLModelMetadata) throws -> Void) -> (url: URL?, notes: [String]) {
        let metadata = MLModelMetadata(author: "Apple Toolbox", shortDescription: "\(task.rawValue) trained on device with Create ML (\(algorithm)).", version: "1")
        do {
            return (try CreateMLModelStore.save(task) { try write($0, metadata) }, [])
        } catch {
            return (nil, ["The model could not be written for export: \(error.localizedDescription)"])
        }
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

    private static func modelFacts(url: URL?, parameters: String) -> [CreateMLMetricRow] {
        let size = url.flatMap(CreateMLModelStore.fileSize)
        return [
            CreateMLMetricRow(title: "Algorithm", training: parameters, validation: ""),
            CreateMLMetricRow(title: "Core ML model size", training: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—", validation: ""),
        ]
    }

    private static func imageValidation(_ option: CreateMLValidationOption) -> MLImageClassifier.ModelParameters.ValidationData {
        switch option {
        case .automatic: .split(strategy: .automatic)
        case .holdOut: .split(strategy: .fixed(ratio: 0.2, seed: 7))
        case .none: .none
        }
    }

    private static func soundValidation(_ option: CreateMLValidationOption) -> MLSoundClassifier.ModelParameters.ValidationData {
        switch option {
        case .automatic: .split(strategy: .automatic)
        case .holdOut: .split(strategy: .fixed(ratio: 0.2, seed: 7))
        case .none: .none
        }
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
    /// Image and sound samples, kept per task so switching tasks does not lose them.
    @Published private(set) var sampleSets: [CreateMLTask: CreateMLSampleSet] = [:]
    /// The label that receives newly added samples.
    @Published var targetLabel = ""
    @Published private(set) var sampleError: String?
    @Published private(set) var isImportingSamples = false
    @Published private(set) var report: CreateMLTrainingReport?
    @Published private(set) var isTraining = false
    @Published var textInput = "The export button crashes the app"
    @Published var featureInputs: [String: String] = [:]
    @Published private(set) var predictions: [CreateMLPrediction] = []
    @Published private(set) var predictedValue: String?
    /// The file classified with the trained image or sound classifier, and the labels Create ML returned.
    @Published private(set) var classifiedFileName: String?
    @Published private(set) var predictedLabels: [String] = []
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
    private var imageClassifier: MLImageClassifier?
    private var soundClassifier: MLSoundClassifier?
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
        "The Create ML framework's text, tabular, image and sound trainers are not available on this platform."
        #endif
    }

    /// Where copied sample files live; the folder is removed with the samples.
    nonisolated static var samplesDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CreateMLSamples", isDirectory: true)
    }

    var hasTrainedModel: Bool { report != nil }
    var samples: CreateMLSampleSet { sampleSets[task] ?? CreateMLSampleSet() }
    /// Nil when the image or sound samples are ready for training.
    var sampleReadiness: String? { samples.readiness(noun: task.sampleNoun) }

    init() { loadSample() }

    func loadSample() {
        #if canImport(TabularData)
        if !task.usesLabeledFiles { csv = CreateMLDataset.sample(for: task) }
        #endif
        report = nil
        predictions = []
        predictedValue = nil
        predictedLabels = []
        classifiedFileName = nil
        sampleError = nil
        if !samples.labels.contains(targetLabel) { targetLabel = samples.labels.first ?? "" }
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        classifier = nil
        regressor = nil
        imageClassifier = nil
        soundClassifier = nil
        #endif
        if Self.isSupported, !isTraining {
            setOutput(task.usesLabeledFiles
                ? "Add at least two labels and a few \(task.sampleNoun)s for each, then train an \(task.rawValue.lowercased()) on this device."
                : "Edit the sample dataset or import a CSV, then train a model on this device.", error: false)
        }
    }

    // MARK: Labels and samples

    func addLabel(_ name: String) {
        var set = samples
        do {
            targetLabel = try set.addLabel(name)
            sampleSets[task] = set
            sampleError = nil
        } catch {
            sampleError = error.localizedDescription
        }
    }

    func removeLabel(_ label: String) {
        var set = samples
        let removed = set.removeLabel(label)
        sampleSets[task] = set
        Self.deleteFiles(removed)
        if targetLabel == label { targetLabel = set.labels.first ?? "" }
    }

    func removeSample(_ id: UUID) {
        var set = samples
        guard let removed = set.removeSample(id: id) else { return }
        sampleSets[task] = set
        Self.deleteFiles([removed])
    }

    /// Copies picked files (file importer) into the samples folder under the selected label.
    func importSamples(from urls: [URL]) {
        let label = targetLabel, task = task
        guard !label.isEmpty else { return sampleError = "Add a label first; new \(task.sampleNoun)s go to the label selected in “Add to label”." }
        isImportingSamples = true
        Task { [weak self] in
            let result = await Self.copySamples(urls)
            self?.finishImport(result, label: label, task: task)
        }
    }

    /// Stores picked photo data (PhotosPicker) as files under the selected label.
    func importSampleData(_ items: [(data: Data, fileExtension: String)]) {
        let label = targetLabel, task = task
        guard !label.isEmpty else { return sampleError = "Add a label first; new \(task.sampleNoun)s go to the label selected in “Add to label”." }
        isImportingSamples = true
        Task { [weak self] in
            let result = await Self.writeSamples(items)
            self?.finishImport(result, label: label, task: task)
        }
    }

    func reportSampleImportFailure(_ message: String) {
        isImportingSamples = false
        sampleError = message
    }

    private func finishImport(_ result: (samples: [CreateMLSample], failures: [String]), label: String, task: CreateMLTask) {
        isImportingSamples = false
        var set = sampleSets[task] ?? CreateMLSampleSet()
        set.add(result.samples, to: label)
        sampleSets[task] = set
        sampleError = result.failures.isEmpty ? nil : result.failures.joined(separator: "\n")
        if !result.samples.isEmpty {
            setOutput("Added \(result.samples.count) \(task.sampleNoun)\(result.samples.count == 1 ? "" : "s") to “\(label)”. \(set.readiness(noun: task.sampleNoun) ?? "Ready to train.")", error: false)
        }
    }

    // MARK: CSV

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

    // MARK: Training

    func train() {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        guard !isTraining else { return }
        if task.usesLabeledFiles {
            if let missing = sampleReadiness { return setOutput(missing, error: true) }
        } else if dataset == nil {
            return
        }
        generation += 1
        let run = generation
        let csv = csv, task = task, validation = validation
        let textAlgorithm = textAlgorithm, regressorAlgorithm = regressorAlgorithm
        let textColumn = textColumn, labelColumn = labelColumn, target = targetColumn
        let columns = dataset?.columns ?? []
        let files = samples.filesByLabel
        isTraining = true
        report = nil
        predictions = []
        predictedValue = nil
        predictedLabels = []
        classifiedFileName = nil
        setOutput("Training a \(task.rawValue.lowercased())\(Self.algorithmSuffix(task, textAlgorithm, regressorAlgorithm)) on \(task.usesLabeledFiles ? "\(samples.sampleCount) \(task.sampleNoun)s" : "\(dataset?.rowCount ?? 0) rows")…", error: false)
        Task { [weak self] in
            switch task {
            case .textClassifier:
                let result = await Self.detached { try CreateMLTrainer.trainTextClassifier(csv: csv, textColumn: textColumn, labelColumn: labelColumn, algorithm: textAlgorithm, validation: validation) }
                guard let self, self.generation == run else { return }
                switch result {
                case .success(let (classifier, report)):
                    self.clearModels()
                    self.classifier = classifier
                    self.finishTraining(report)
                case .failure(let error): self.failTraining(error)
                }
            case .tabularRegressor:
                let result = await Self.detached { try CreateMLTrainer.trainRegressor(csv: csv, target: target, algorithm: regressorAlgorithm, validation: validation) }
                guard let self, self.generation == run else { return }
                switch result {
                case .success(let (regressor, report)):
                    self.clearModels()
                    self.regressor = regressor
                    self.trainedFeatures = columns.filter { $0.name != target }
                    self.featureInputs = Dictionary(uniqueKeysWithValues: self.trainedFeatures.map { ($0.name, self.featureInputs[$0.name] ?? $0.example) })
                    self.finishTraining(report)
                case .failure(let error): self.failTraining(error)
                }
            case .imageClassifier:
                let result = await Self.detached { try CreateMLTrainer.trainImageClassifier(filesByLabel: files, validation: validation) }
                guard let self, self.generation == run else { return }
                switch result {
                case .success(let (classifier, report)):
                    self.clearModels()
                    self.imageClassifier = classifier
                    self.finishTraining(report)
                case .failure(let error): self.failTraining(error)
                }
            case .soundClassifier:
                let result = await Self.detached { try CreateMLTrainer.trainSoundClassifier(filesByLabel: files, validation: validation) }
                guard let self, self.generation == run else { return }
                switch result {
                case .success(let (classifier, report)):
                    self.clearModels()
                    self.soundClassifier = classifier
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

    // MARK: Prediction

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

    /// Classifies a picked image or audio file with the trained image or sound classifier.
    func classifyFile(at url: URL) {
        let task = task
        Task { [weak self] in
            let copied = await Self.copySamples([url])
            guard let sample = copied.samples.first else {
                self?.setOutput(copied.failures.first ?? "The file could not be read.", error: true)
                return
            }
            self?.classify(sample.url, name: sample.name, task: task)
        }
    }

    /// Classifies picked photo data with the trained image classifier.
    func classifyImageData(_ data: Data, fileExtension: String) {
        let task = task
        Task { [weak self] in
            let written = await Self.writeSamples([(data, fileExtension)])
            guard let sample = written.samples.first else {
                self?.setOutput(written.failures.first ?? "The photo could not be stored.", error: true)
                return
            }
            self?.classify(sample.url, name: "Photo", task: task)
        }
    }

    private func classify(_ url: URL, name: String, task: CreateMLTask) {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        let work: @Sendable () throws -> [String]
        if task == .imageClassifier, let imageClassifier {
            work = { try CreateMLTrainer.classify(imageAt: url, with: imageClassifier) }
        } else if task == .soundClassifier, let soundClassifier {
            work = { try CreateMLTrainer.classify(soundAt: url, with: soundClassifier) }
        } else {
            try? FileManager.default.removeItem(at: url)
            return setOutput("Train a \(task.rawValue.lowercased()) first.", error: true)
        }
        Task { [weak self] in
            let outcome = await Self.detached(work)
            try? FileManager.default.removeItem(at: url)
            guard let self else { return }
            self.classifiedFileName = name
            switch outcome {
            case .success(let labels):
                self.predictedLabels = labels
                let api = task == .imageClassifier ? "prediction(from:)" : "predictions(from:)"
                self.setOutput("\(api) returned \(labels.isEmpty ? "no label" : labels.map { "“\($0)”" }.joined(separator: ", ")) for \(name).", error: labels.isEmpty)
            case .failure(let error):
                self.predictedLabels = []
                self.setOutput("Prediction failed: \(error.localizedDescription)", error: true)
            }
        }
        #endif
    }

    var trainedFeatureColumns: [CreateMLColumnInfo] { trainedFeatures }

    private func clearModels() {
        #if canImport(CreateML) && (os(iOS) || os(macOS))
        classifier = nil
        regressor = nil
        imageClassifier = nil
        soundClassifier = nil
        #endif
    }

    private func finishTraining(_ report: CreateMLTrainingReport) {
        self.report = report
        isTraining = false
        let headline = report.metrics.first.map { "\($0.title): training \($0.training), validation \($0.validation)" } ?? ""
        let saved = report.modelURL.map { " Saved as \($0.lastPathComponent) for export and for the Core ML experiment." } ?? ""
        setOutput("Trained on device in \(report.seconds.formatted(.number.precision(.fractionLength(2)))) s. \(headline)\(saved)", error: false)
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

    private static func algorithmSuffix(_ task: CreateMLTask, _ text: CreateMLTextAlgorithm, _ regressor: CreateMLRegressorAlgorithm) -> String {
        switch task {
        case .textClassifier: " (\(text.rawValue))"
        case .tabularRegressor: " (\(regressor.rawValue))"
        case .imageClassifier, .soundClassifier: ""
        }
    }

    /// Runs Create ML work off the main actor and hands back only Sendable values.
    @concurrent nonisolated private static func detached<T: Sendable>(_ body: @Sendable () throws -> T) async -> Result<T, Error> {
        Result { try body() }
    }

    /// Copies user-picked files into the samples folder (the originals are only readable while security-scoped access lasts).
    @concurrent nonisolated private static func copySamples(_ urls: [URL]) async -> (samples: [CreateMLSample], failures: [String]) {
        var samples: [CreateMLSample] = [], failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let id = UUID()
                let destination = try sampleURL(id: id, fileExtension: url.pathExtension)
                try FileManager.default.copyItem(at: url, to: destination)
                samples.append(CreateMLSample(id: id, url: destination, name: url.lastPathComponent))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (samples, failures)
    }

    @concurrent nonisolated private static func writeSamples(_ items: [(data: Data, fileExtension: String)]) async -> (samples: [CreateMLSample], failures: [String]) {
        var samples: [CreateMLSample] = [], failures: [String] = []
        for (index, item) in items.enumerated() {
            do {
                let id = UUID()
                let destination = try sampleURL(id: id, fileExtension: item.fileExtension)
                try item.data.write(to: destination)
                samples.append(CreateMLSample(id: id, url: destination, name: "Photo \(index + 1).\(destination.pathExtension)"))
            } catch {
                failures.append("Photo \(index + 1): \(error.localizedDescription)")
            }
        }
        return (samples, failures)
    }

    nonisolated private static func sampleURL(id: UUID, fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: samplesDirectory, withIntermediateDirectories: true)
        return samplesDirectory.appendingPathComponent(id.uuidString).appendingPathExtension(fileExtension.isEmpty ? "dat" : fileExtension)
    }

    private static func deleteFiles(_ samples: [CreateMLSample]) {
        for sample in samples { try? FileManager.default.removeItem(at: sample.url) }
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
