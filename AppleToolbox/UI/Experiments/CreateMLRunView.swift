import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct CreateMLRunView: View {
    @StateObject private var createML = CreateMLExperimentService()

    var body: some View {
        #if os(iOS) || os(macOS)
        if CreateMLExperimentService.isSupported {
            CreateMLTrainingForm(createML: createML)
        }
        #endif
        OutputView(text: createML.output, isError: createML.isError)
    }
}

#if os(iOS) || os(macOS)
private struct CreateMLTrainingForm: View {
    @ObservedObject var createML: CreateMLExperimentService
    @State private var showingImporter = false

    var body: some View {
        Picker("Task", selection: $createML.task) {
            ForEach(CreateMLTask.allCases) { Text($0.rawValue).tag($0) }
        }
        .disabled(createML.isTraining)
        switch createML.task {
        case .textClassifier:
            Picker("Algorithm", selection: $createML.textAlgorithm) {
                ForEach(CreateMLTextAlgorithm.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(createML.isTraining)
        case .tabularRegressor:
            Picker("Algorithm", selection: $createML.regressorAlgorithm) {
                ForEach(CreateMLRegressorAlgorithm.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(createML.isTraining)
        }
        Picker("Validation", selection: $createML.validation) {
            ForEach(CreateMLValidationOption.allCases) { Text($0.rawValue).tag($0) }
        }
        .disabled(createML.isTraining)
        datasetSection
        if createML.isTraining {
            HStack {
                ProgressView()
                Text("Training on device…").foregroundStyle(.secondary)
                Spacer()
                Button("Stop Waiting", systemImage: "stop.fill", action: createML.stop)
            }
            .experimentSession(createML)
        } else {
            Button("Train Model", systemImage: "hammer", action: createML.train)
                .buttonStyle(.borderedProminent)
                .disabled(!canTrain)
                .experimentSession(createML)
        }
        if let report = createML.report {
            CreateMLReportSections(report: report)
            predictionSection(report)
        }
    }

    @ViewBuilder private var datasetSection: some View {
        Section("Training data (CSV)") {
            TextEditor(text: $createML.csv)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 160, maxHeight: 260)
                .disabled(createML.isTraining)
            HStack {
                Button("Load Sample", systemImage: "arrow.counterclockwise", action: createML.loadSample)
                Spacer()
                Button("Import CSV…", systemImage: "doc.badge.plus") { showingImporter = true }
                    #if canImport(UniformTypeIdentifiers)
                    .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
                        switch result {
                        case .success(let urls): if let url = urls.first { createML.importCSV(from: url) }
                        case .failure(let error): createML.reportImportFailure(error)
                        }
                    }
                    #endif
            }
            .buttonStyle(.borderless)
            .disabled(createML.isTraining)
            if let error = createML.datasetError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let dataset = createML.dataset {
                LabeledContent("Rows", value: "\(dataset.rowCount)")
                LabeledContent("Columns") {
                    Text(dataset.columns.map { "\($0.name): \($0.kind.rawValue)" }.joined(separator: ", "))
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                }
                switch createML.task {
                case .textClassifier:
                    Picker("Text column", selection: $createML.textColumn) {
                        if dataset.textColumns.isEmpty { Text("No text column").tag("") }
                        ForEach(dataset.textColumns) { Text($0.name).tag($0.name) }
                    }
                    Picker("Label column", selection: $createML.labelColumn) {
                        if dataset.textColumns.isEmpty { Text("No text column").tag("") }
                        ForEach(dataset.textColumns) { Text($0.name).tag($0.name) }
                    }
                    if !createML.labelCounts.isEmpty {
                        LabeledContent("Labels") {
                            Text(createML.labelCounts.map { "\($0.label) ×\($0.count)" }.joined(separator: " · "))
                                .font(.caption)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                case .tabularRegressor:
                    Picker("Target column", selection: $createML.targetColumn) {
                        if dataset.numericColumns.isEmpty { Text("No numeric column").tag("") }
                        ForEach(dataset.numericColumns) { Text($0.name).tag($0.name) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func predictionSection(_ report: CreateMLTrainingReport) -> some View {
        Section("Try the trained model") {
            switch report.task {
            case .textClassifier:
                TextField("Text to classify", text: $createML.textInput, axis: .vertical)
                Button("Classify", systemImage: "text.magnifyingglass", action: createML.predict)
                    .disabled(createML.textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(createML.predictions) { prediction in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(prediction.label).fontWeight(prediction.id == createML.predictions.first?.id ? .semibold : .regular)
                            Spacer()
                            Text(prediction.confidence.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(max(prediction.confidence ?? 0, 0), 1))
                    }
                }
            case .tabularRegressor:
                ForEach(createML.trainedFeatureColumns) { column in
                    LabeledContent("\(column.name) (\(column.kind.rawValue))") {
                        TextField(column.example, text: featureBinding(column.name))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(column.kind.isNumeric ? .decimalPad : .default)
                            #endif
                    }
                }
                Button("Predict", systemImage: "function", action: createML.predict)
                if let value = createML.predictedValue {
                    LabeledContent("Predicted value", value: value)
                }
            }
        }
    }

    private var canTrain: Bool {
        guard let dataset = createML.dataset, dataset.rowCount > 1 else { return false }
        switch createML.task {
        case .textClassifier: return !createML.textColumn.isEmpty && !createML.labelColumn.isEmpty && createML.textColumn != createML.labelColumn
        case .tabularRegressor: return !createML.targetColumn.isEmpty && dataset.columns.count > 1
        }
    }

    private func featureBinding(_ name: String) -> Binding<String> {
        Binding(get: { createML.featureInputs[name, default: ""] }, set: { createML.featureInputs[name] = $0 })
    }
}

private struct CreateMLReportSections: View {
    let report: CreateMLTrainingReport

    var body: some View {
        Section("Metrics") {
            HStack {
                Text("Metric").fontWeight(.semibold)
                Spacer()
                Text("Training").frame(width: 90, alignment: .trailing)
                Text("Validation").frame(width: 90, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(report.metrics) { row in
                HStack {
                    Text(row.title)
                    Spacer()
                    Text(row.training).frame(width: 90, alignment: .trailing)
                    Text(row.validation).frame(width: 90, alignment: .trailing)
                }
                .font(.body.monospacedDigit())
            }
        }
        if !report.labelMetrics.isEmpty {
            Section("Precision / recall per label") {
                ForEach(report.labelMetrics) { metric in
                    LabeledContent(metric.label, value: "P \(metric.precision) · R \(metric.recall)")
                }
            }
        }
        if !report.confusions.isEmpty {
            Section("Confusions") {
                ForEach(report.confusions, id: \.self) { Text($0).font(.callout.monospacedDigit()) }
            }
        }
        Section("Trained model") {
            LabeledContent("Task", value: report.task.rawValue)
            LabeledContent("Rows", value: "\(report.rows)")
            LabeledContent("Training time", value: "\(report.seconds.formatted(.number.precision(.fractionLength(2)))) s")
            ForEach(report.modelFacts) { fact in
                LabeledContent(fact.title) { Text(fact.training).multilineTextAlignment(.trailing) }
            }
            ForEach(report.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
#endif
