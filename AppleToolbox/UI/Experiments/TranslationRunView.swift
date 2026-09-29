import SwiftUI
#if canImport(Translation) && (os(iOS) || os(macOS))
import Translation
#endif

struct TranslationRunView: View {
    @StateObject private var translator = TranslationExperimentService()

    var body: some View {
        if translator.isSupported {
            Picker("From", selection: $translator.sourceID) {
                Text("Detect from text").tag(TranslationExperimentService.detectSourceID)
                ForEach(translator.languages) { Text($0.name).tag($0.id) }
            }
            Picker("To", selection: $translator.targetID) {
                if translator.languages.isEmpty { Text("Loading…").tag("") }
                ForEach(translator.languages) { Text($0.name).tag($0.id) }
            }
            LabeledContent("Pair status") { Text(translator.pairStatus).multilineTextAlignment(.trailing) }
            TextField("Text to translate", text: $translator.input, axis: .vertical)
            Button(translator.isTranslating ? "Translating…" : "Translate", systemImage: "translate", action: translator.requestTranslation)
                .buttonStyle(.borderedProminent)
                .disabled(translator.isTranslating || translator.languages.isEmpty || translator.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #if canImport(Translation) && (os(iOS) || os(macOS))
                .translationTask(translator.configuration) { session in await translator.translate(using: session) }
                #endif
            if !translator.translation.isEmpty {
                Section("Translation") { Text(translator.translation) }
            }
        }
        OutputView(text: translator.output, isError: translator.isError)
            .task { await translator.loadLanguages() }
            .task(id: statusKey) {
                // Debounced so typing in detect mode does not query the system on every keystroke.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await translator.refreshStatus()
            }
    }

    private var statusKey: String {
        let detecting = translator.sourceID == TranslationExperimentService.detectSourceID
        return [translator.sourceID, translator.targetID, detecting ? translator.input : ""].joined(separator: "|")
    }
}
