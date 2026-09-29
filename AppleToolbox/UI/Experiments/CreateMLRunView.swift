import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if os(iOS) || os(macOS)
import PhotosUI
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
        case .imageClassifier:
            LabeledContent("Algorithm", value: "Transfer learning · Vision scene print + logistic regression")
        case .soundClassifier:
            LabeledContent("Algorithm", value: "Transfer learning · audio feature print + logistic regression")
        }
        Picker("Validation", selection: $createML.validation) {
            ForEach(CreateMLValidationOption.allCases) { Text($0.rawValue).tag($0) }
        }
        .disabled(createML.isTraining)
        if createML.task.usesLabeledFiles {
            CreateMLSampleEditor(createML: createML)
        } else {
            datasetSection
        }
        if createML.isTraining {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProgressView()
                    Text("Training on device…").foregroundStyle(.secondary)
                    Spacer()
                    Button(createML.canCancelTraining ? "Stop Training" : "Stop Waiting", systemImage: "stop.fill", action: createML.stop)
                }
                if !createML.canCancelTraining {
                    Text("Create ML cannot interrupt this trainer: stopping discards the model, but the current step finishes in the background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
            if let url = report.modelURL {
                Section("Export") {
                    ShareLink(item: url, preview: SharePreview(url.lastPathComponent)) {
                        Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                    Text("MLModel written by Create ML's write(to:metadata:) into the app's Trained Models folder. Open the Core ML experiment to compile it, run predictions and compare compute units.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
                case .imageClassifier, .soundClassifier:
                    EmptyView()
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
            case .imageClassifier, .soundClassifier:
                CreateMLFileClassifier(createML: createML, task: report.task)
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
        if createML.task.usesLabeledFiles { return createML.sampleReadiness == nil && !createML.isImportingSamples }
        guard let dataset = createML.dataset, dataset.rowCount > 1 else { return false }
        switch createML.task {
        case .textClassifier: return !createML.textColumn.isEmpty && !createML.labelColumn.isEmpty && createML.textColumn != createML.labelColumn
        case .tabularRegressor: return !createML.targetColumn.isEmpty && dataset.columns.count > 1
        case .imageClassifier, .soundClassifier: return false
        }
    }

    private func featureBinding(_ name: String) -> Binding<String> {
        Binding(get: { createML.featureInputs[name, default: ""] }, set: { createML.featureInputs[name] = $0 })
    }
}

/// Labels with their image or sound files; Create ML trains from them as `DataSource.filesByLabel`.
private struct CreateMLSampleEditor: View {
    @ObservedObject var createML: CreateMLExperimentService
    @State private var newLabel = ""
    @State private var showingImporter = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        let task = createML.task
        let samples = createML.samples
        Section("Training \(task.sampleNoun)s by label") {
            HStack {
                TextField("New label, e.g. \(task == .soundClassifier ? "clap" : "cat")", text: $newLabel)
                    .onSubmit(addLabel)
                Button("Add Label", systemImage: "plus", action: addLabel)
                    .disabled(CreateMLSampleSet.normalized(newLabel).isEmpty)
            }
            .disabled(createML.isTraining)
            if !samples.isEmpty {
                Picker("Add to label", selection: $createML.targetLabel) {
                    ForEach(samples.labels, id: \.self) { Text($0).tag($0) }
                }
                .disabled(createML.isTraining)
                HStack {
                    if task == .imageClassifier {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 50, matching: .images) {
                            Label("Add Photos…", systemImage: "photo.on.rectangle")
                        }
                    }
                    Spacer()
                    Button(task == .imageClassifier ? "Add Image Files…" : "Add Audio Files…", systemImage: "doc.badge.plus") { showingImporter = true }
                        #if canImport(UniformTypeIdentifiers)
                        .fileImporter(isPresented: $showingImporter, allowedContentTypes: task == .imageClassifier ? [.image] : [.audio], allowsMultipleSelection: true) { result in
                            switch result {
                            case .success(let urls): createML.importSamples(from: urls)
                            case .failure(let error): createML.reportSampleImportFailure("File import error: \(error.localizedDescription)")
                            }
                        }
                        #endif
                }
                .buttonStyle(.borderless)
                .disabled(createML.isTraining || createML.isImportingSamples || createML.targetLabel.isEmpty)
            }
            if createML.isImportingSamples {
                ProgressView("Copying samples…")
            }
            ForEach(samples.groups) { group in
                DisclosureGroup {
                    ForEach(group.samples) { sample in
                        HStack {
                            Text(sample.name).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle", role: .destructive) { createML.removeSample(sample.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Remove Label “\(group.label)”", systemImage: "trash", role: .destructive) { createML.removeLabel(group.label) }
                        .buttonStyle(.borderless)
                } label: {
                    LabeledContent(group.label, value: "\(group.samples.count) \(task.sampleNoun)\(group.samples.count == 1 ? "" : "s")")
                }
                .disabled(createML.isTraining)
            }
            if let error = createML.sampleError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text(createML.sampleReadiness ?? "Ready: \(samples.sampleCount) \(task.sampleNoun)s in \(samples.labels.count) labels.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(task == .imageClassifier
                 ? "Create ML extracts Vision scene-print features from every image on device and trains a classifier on top; more varied photos per label generalize better."
                 : "Create ML splits every clip into ~1 s windows, extracts audio feature prints on device and trains a classifier on top; clips shorter than a window cannot be used.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: photoItems) { _, items in load(items) }
    }

    private func addLabel() {
        createML.addLabel(newLabel)
        if createML.sampleError == nil { newLabel = "" }
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            var loaded: [(data: Data, fileExtension: String)] = []
            var failures = 0
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append((data, item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"))
                } else {
                    failures += 1
                }
            }
            if loaded.isEmpty {
                createML.reportSampleImportFailure("None of the \(items.count) picked photos could be loaded.")
            } else {
                createML.importSampleData(loaded)
                if failures > 0 { createML.reportSampleImportFailure("\(failures) of \(items.count) photos could not be loaded.") }
            }
        }
    }
}

/// Picks an image or audio file and classifies it with the Create ML model trained in this session.
private struct CreateMLFileClassifier: View {
    @ObservedObject var createML: CreateMLExperimentService
    let task: CreateMLTask
    @State private var showingImporter = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        HStack {
            if task == .imageClassifier {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Classify a Photo…", systemImage: "photo")
                }
            }
            Spacer()
            Button(task == .imageClassifier ? "Classify an Image File…" : "Classify an Audio File…", systemImage: "doc.viewfinder") { showingImporter = true }
                #if canImport(UniformTypeIdentifiers)
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: task == .imageClassifier ? [.image] : [.audio], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): if let url = urls.first { createML.classifyFile(at: url) }
                    case .failure(let error): createML.reportImportFailure(error)
                    }
                }
                #endif
        }
        .buttonStyle(.borderless)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    return createML.reportSampleImportFailure("The picked photo could not be loaded.")
                }
                createML.classifyImageData(data, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
            }
        }
        if let name = createML.classifiedFileName {
            LabeledContent("File", value: name)
            LabeledContent("Predicted label") {
                Text(createML.predictedLabels.isEmpty ? "—" : createML.predictedLabels.joined(separator: ", ")).fontWeight(.semibold)
            }
        }
        Text(task == .imageClassifier
             ? "MLImageClassifier.prediction(from:) returns only the top label. The Core ML experiment runs the exported model and shows every label's probability."
             : "MLSoundClassifier.predictions(from:) returns one label per file. The Core ML experiment runs the exported model on raw audio windows.")
            .font(.caption)
            .foregroundStyle(.secondary)
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
            LabeledContent(report.task.usesLabeledFiles ? "Samples" : "Rows", value: "\(report.rows)")
            LabeledContent("Training time", value: "\(report.seconds.formatted(.number.precision(.fractionLength(2)))) s")
            ForEach(report.modelFacts) { fact in
                LabeledContent(fact.title) { Text(fact.training).multilineTextAlignment(.trailing) }
            }
            ForEach(report.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
#endif
