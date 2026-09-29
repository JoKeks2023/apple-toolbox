import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if os(iOS) || os(macOS)
import PhotosUI
#endif

struct CoreMLRunView: View {
    @StateObject private var coreML = CoreMLExperimentService()
    @State private var showingImporter = false

    var body: some View {
        Section("Compute devices") {
            if coreML.devices.isEmpty {
                Text("Core ML reported no compute devices.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(coreML.devices) { device in
                LabeledContent {
                    Text(device.detail).multilineTextAlignment(.trailing)
                } label: {
                    Label(device.kind, systemImage: device.symbol)
                }
            }
        }
        Picker("Compute units", selection: $coreML.computeUnits) {
            ForEach(CoreMLComputeUnitsOption.allCases) { Text($0.rawValue).tag($0) }
        }
        .disabled(coreML.isLoading || coreML.isPredicting)
        Section("Trained on this device") {
            if coreML.trainedModels.isEmpty {
                Text("No trained model yet. Train one in the Create ML experiment on iPhone, iPad or Mac; it is saved to the app's Trained Models folder and appears here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $coreML.selectedTrainedModel) {
                    ForEach(coreML.trainedModels) { Text($0.title).tag($0.id) }
                }
                Button("Compile & Load", systemImage: "cpu", action: coreML.loadTrainedModel)
                    .disabled(coreML.isLoading || coreML.isPredicting)
            }
        }
        .onAppear(perform: coreML.refreshTrainedModels)
        #if os(tvOS)
        Text("tvOS has no document picker, so a model cannot be imported here.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #else
        Button(coreML.isLoading ? "Loading Model…" : "Import Model", systemImage: "square.and.arrow.down") { showingImporter = true }
            .buttonStyle(.bordered)
            .disabled(coreML.isLoading || coreML.isPredicting)
            .experimentSession(coreML)
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { coreML.importModel(from: url) }
                case .failure(let error): coreML.reportImportFailure(error)
                }
            }
            #endif
        #endif
        if let summary = coreML.summary {
            Section("Model") {
                LabeledContent("File", value: summary.fileName)
                LabeledContent("Source") { Text(summary.origin).multilineTextAlignment(.trailing) }
                LabeledContent("Configured compute units", value: summary.computeUnits)
                FactRows(facts: summary.facts)
            }
            Section("Metadata") { FactRows(facts: summary.metadata) }
            FeatureSection(title: "Inputs", features: summary.inputs)
            FeatureSection(title: "Outputs", features: summary.outputs)
            CoreMLPredictionSection(coreML: coreML)
        }
        OutputView(text: coreML.output, isError: coreML.isError)
    }

    #if canImport(UniformTypeIdentifiers) && !os(tvOS)
    /// .mlpackage and .mlmodelc are directories without a system-declared package type, so folders are selectable too.
    private static let importTypes: [UTType] = CoreMLExperimentService.modelExtensions.compactMap { UTType(filenameExtension: $0) } + [.folder]
    #endif
}

/// Builds the model's inputs, runs MLModel.prediction(from:) repeatedly and compares compute-unit settings.
private struct CoreMLPredictionSection: View {
    @ObservedObject var coreML: CoreMLExperimentService
    #if os(iOS) || os(macOS)
    @State private var photoItem: PhotosPickerItem?
    #endif
    @State private var showingImageImporter = false

    var body: some View {
        Section("Prediction input") {
            ForEach(coreML.inputFields) { field in
                switch field.kind {
                case .text:
                    TextField(field.name, text: binding(field.name), axis: .vertical)
                case .integer, .double:
                    LabeledContent("\(field.name) (\(field.kind.summary))") {
                        TextField("0", text: binding(field.name))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(field.kind == .integer ? .numberPad : .decimalPad)
                            #endif
                    }
                case .image:
                    LabeledContent("\(field.name) (\(field.kind.summary))") {
                        Text(coreML.inputImageName ?? "No image chosen").foregroundStyle(.secondary)
                    }
                    imagePickers
                case .multiArray, .unsupported:
                    LabeledContent(field.name) { Text(field.kind.summary).font(.caption).multilineTextAlignment(.trailing) }
                }
            }
        }
        Section("Predictions") {
            Picker("Repetitions", selection: $coreML.iterations) {
                ForEach(InferenceIterations.allCases) { Text($0.title).tag($0) }
            }
            .disabled(coreML.isPredicting)
            if coreML.isPredicting {
                HStack {
                    ProgressView()
                    Text("Predicting…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop", systemImage: "stop.fill", action: coreML.stop)
                }
            } else {
                Button("Predict with \(coreML.computeUnits.shortName)", systemImage: "play.fill") { coreML.runPredictions(allUnits: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(coreML.predictionBlocker != nil || coreML.isLoading)
                Button("Compare All Compute Units", systemImage: "chart.bar.xaxis") { coreML.runPredictions(allUnits: true) }
                    .disabled(coreML.predictionBlocker != nil || coreML.isLoading)
            }
            if let blocker = coreML.predictionBlocker {
                Text(blocker).font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(coreML.results) { result in
            Section(result.units.rawValue) {
                LabeledContent("Model load", value: InferenceTimingStats.format(result.loadMilliseconds))
                LabeledContent("First prediction", value: InferenceTimingStats.format(result.timings.firstMilliseconds))
                if result.timings.runs > 1 {
                    LabeledContent("Median (warm)", value: InferenceTimingStats.format(result.timings.medianMilliseconds))
                    LabeledContent("Mean · min–max", value: "\(InferenceTimingStats.format(result.timings.meanMilliseconds)) · \(InferenceTimingStats.format(result.timings.minMilliseconds))–\(InferenceTimingStats.format(result.timings.maxMilliseconds))")
                }
                Text(result.plannedDevices).font(.caption).foregroundStyle(.secondary)
                ForEach(result.outputs) { output in
                    LabeledContent(output.name) { Text(output.value).font(.callout.monospacedDigit()).multilineTextAlignment(.trailing) }
                }
            }
            .monospacedDigit()
        }
    }

    @ViewBuilder private var imagePickers: some View {
        HStack {
            #if os(iOS) || os(macOS)
            PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose Photo…", systemImage: "photo") }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    photoItem = nil
                    Task {
                        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                        coreML.setInputImage(data: data, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg", name: "Photo")
                    }
                }
            #endif
            Spacer()
            #if !os(tvOS)
            Button("Image File…", systemImage: "doc") { showingImageImporter = true }
                #if canImport(UniformTypeIdentifiers)
                .fileImporter(isPresented: $showingImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                    if case .success(let urls) = result, let url = urls.first { coreML.setInputImage(fileURL: url) }
                }
                #endif
            #endif
        }
        .buttonStyle(.borderless)
        .disabled(coreML.isPredicting)
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(get: { coreML.inputTexts[name, default: ""] }, set: { coreML.inputTexts[name] = $0 })
    }
}

private struct FactRows: View {
    let facts: [ModelFact]

    var body: some View {
        ForEach(facts) { fact in
            LabeledContent(fact.title) { Text(fact.value).multilineTextAlignment(.trailing) }
        }
    }
}

private struct FeatureSection: View {
    let title: String
    let features: [ModelFeatureInfo]

    var body: some View {
        Section(title) {
            if features.isEmpty {
                Text("None").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(features) { feature in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(feature.name).font(.body.monospaced())
                        Spacer()
                        Text(feature.type).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
