import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
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
        .disabled(coreML.isLoading)
        #if os(tvOS)
        Text("tvOS has no document picker, so a model cannot be imported here.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #else
        Button(coreML.isLoading ? "Loading Model…" : "Import Model", systemImage: "square.and.arrow.down") { showingImporter = true }
            .buttonStyle(.borderedProminent)
            .disabled(coreML.isLoading)
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
        }
        OutputView(text: coreML.output, isError: coreML.isError)
    }

    #if canImport(UniformTypeIdentifiers) && !os(tvOS)
    /// .mlpackage and .mlmodelc are directories without a system-declared package type, so folders are selectable too.
    private static let importTypes: [UTType] = CoreMLExperimentService.modelExtensions.compactMap { UTType(filenameExtension: $0) } + [.folder]
    #endif
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
