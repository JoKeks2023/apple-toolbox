import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct CoreAIRunView: View {
    @StateObject private var coreAI = CoreAIExperimentService()
    @State private var showingImporter = false

    var body: some View {
        Section("Device") {
            ForEach(coreAI.deviceFacts) { fact in
                LabeledContent(fact.title) { Text(fact.value).multilineTextAlignment(.trailing) }
            }
        }
        #if os(iOS) || os(macOS)
        if coreAI.status == .available {
            Picker("Compute preference", selection: $coreAI.preference) {
                ForEach(CoreAIComputePreference.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(coreAI.isBusy)
            Button(coreAI.isBusy ? "Working…" : "Import .aimodel…", systemImage: "square.and.arrow.down") { showingImporter = true }
                .buttonStyle(.borderedProminent)
                .disabled(coreAI.isBusy)
                .experimentSession(coreAI)
                #if canImport(UniformTypeIdentifiers)
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): if let url = urls.first { coreAI.importModel(from: url) }
                    case .failure(let error): coreAI.reportImportFailure(error)
                    }
                }
                #endif
            if let name = coreAI.modelName {
                Section("Asset · \(name)") {
                    FactList(facts: coreAI.assetFacts + coreAI.loadFacts)
                    Button("Delete Cached Specializations", systemImage: "trash", action: coreAI.clearCache)
                        .disabled(coreAI.isBusy)
                }
            }
            if !coreAI.functions.isEmpty {
                Section("Inference function") {
                    Picker("Function", selection: $coreAI.selectedFunction) {
                        ForEach(coreAI.functions) { Text($0.name).tag($0.name) }
                    }
                    if let info = coreAI.selectedFunctionInfo {
                        ForEach(info.inputs) { value in LabeledContent("in · \(value.name)") { Text(value.summary).font(.caption).multilineTextAlignment(.trailing) } }
                        ForEach(info.outputs) { value in LabeledContent("out · \(value.name)") { Text(value.summary).font(.caption).multilineTextAlignment(.trailing) } }
                        if !info.states.isEmpty { LabeledContent("States", value: info.states.joined(separator: ", ")) }
                        if let blocker = info.blocker { Text(blocker).font(.caption).foregroundStyle(.orange) }
                    }
                    Picker("Repetitions", selection: $coreAI.iterations) {
                        ForEach(InferenceIterations.allCases) { Text($0.title).tag($0) }
                    }
                    if coreAI.isBusy {
                        Button("Stop", systemImage: "stop.fill", action: coreAI.stop)
                    } else {
                        Button("Run with Synthetic Inputs", systemImage: "play.fill", action: coreAI.run)
                            .disabled(coreAI.selectedFunctionInfo?.blocker != nil)
                    }
                }
            }
            ForEach(coreAI.results) { result in
                Section("\(result.function) · \(result.preference.rawValue)") {
                    LabeledContent("First run", value: InferenceTimingStats.format(result.timings.firstMilliseconds))
                    if result.timings.runs > 1 {
                        LabeledContent("Median (warm)", value: InferenceTimingStats.format(result.timings.medianMilliseconds))
                        LabeledContent("Mean · min–max", value: "\(InferenceTimingStats.format(result.timings.meanMilliseconds)) · \(InferenceTimingStats.format(result.timings.minMilliseconds))–\(InferenceTimingStats.format(result.timings.maxMilliseconds))")
                    }
                    ForEach(result.outputs) { output in
                        LabeledContent(output.name) { Text(output.value).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing) }
                    }
                }
                .monospacedDigit()
            }
        }
        #endif
        OutputView(text: coreAI.output, isError: coreAI.isError)
    }

    #if canImport(UniformTypeIdentifiers) && (os(iOS) || os(macOS))
    /// .aimodel is a folder package declared by Xcode, not by the OS, so folders are selectable too.
    private static let importTypes: [UTType] = [UTType(filenameExtension: CoreAIExperimentService.modelExtension, conformingTo: .package), .folder, .package].compactMap { $0 }
    #endif
}

private struct FactList: View {
    let facts: [ModelFact]

    var body: some View {
        ForEach(facts) { fact in
            LabeledContent(fact.title) { Text(fact.value).font(.caption).multilineTextAlignment(.trailing) }
        }
    }
}
