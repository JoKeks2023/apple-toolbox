import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if os(iOS) || os(macOS)
import PhotosUI
#endif

struct FoundationModelsImageRunView: View {
    @StateObject private var model = FoundationModelsImageService()
    #if os(iOS) || os(macOS)
    @State private var photoItem: PhotosPickerItem?
    #endif
    @State private var showingImporter = false

    var body: some View {
        Section("Model") {
            ForEach(model.facts) { fact in
                LabeledContent(fact.title) { Text(fact.value).multilineTextAlignment(.trailing) }
            }
            Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
        }
        AIExecutionSection(facts: model.execution)
        #if os(iOS) || os(macOS)
        if model.status == .available {
            Section("Image") {
                let pickerTitle = model.image == nil ? "Choose Photo…" : "Choose Another Photo…"
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) { Label(pickerTitle, systemImage: "photo") }
                    Spacer()
                    Button("Image File…", systemImage: "doc") { showingImporter = true }
                        #if canImport(UniformTypeIdentifiers)
                        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                            switch result {
                            case .success(let urls): if let url = urls.first { loadFile(url) }
                            case .failure(let error): model.reportImageFailure("File import error: \(error.localizedDescription)")
                            }
                        }
                        #endif
                }
                .buttonStyle(.borderless)
                .disabled(model.isGenerating)
                if let image = model.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(model.imageName ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            Section("Prompt") {
                Picker("Vision tool", selection: $model.tool) {
                    ForEach(FMVisionTool.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(model.isGenerating)
                if model.tool != .none, !FoundationModelsImageService.visionToolsInSDK {
                    Text("_Vision_FoundationModels is not in this build's SDK, so no Vision tool can be offered.").font(.caption).foregroundStyle(.red)
                }
                TextField("Question about the image", text: $model.question, axis: .vertical)
                if model.isGenerating {
                    Button("Stop Generating", systemImage: "stop.fill", action: model.stop).buttonStyle(.borderedProminent)
                        .experimentSession(model)
                } else {
                    Button("Ask About Image", systemImage: "sparkles", action: model.ask).buttonStyle(.borderedProminent)
                        .disabled(!model.canAsk)
                        .experimentSession(model)
                }
            }
            if !model.response.isEmpty {
                Section("Streamed answer") { Text(model.response) }
            }
            if !model.toolEvents.isEmpty {
                Section("Tool calls in the transcript") {
                    ForEach(model.toolEvents) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.subheadline.weight(.semibold))
                            Text(event.text).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        #endif
        OutputView(text: model.output, isError: model.isError)
    }

    #if os(iOS) || os(macOS)
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoItem = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return model.reportImageFailure("The picked photo could not be loaded.") }
            model.setImage(data: data, name: "Photo")
        }
    }

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return model.reportImageFailure("\(url.lastPathComponent) could not be read.") }
        model.setImage(data: data, name: url.lastPathComponent)
    }
    #endif
}

/// Per-feature statement of where Foundation Models runs (SPEC §21: on-device only vs. internet/PCC).
struct AIExecutionSection: View {
    let facts: [AIExecutionFact]

    var body: some View {
        Section("Where it runs") {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(fact.feature)
                        Spacer()
                        Text(fact.place.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(fact.place == .onDevice ? .green : .orange)
                    }
                    Text(fact.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
