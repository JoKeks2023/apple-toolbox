import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct SpeechAnalyzerRunView: View {
    @StateObject private var speech = SpeechAnalyzerExperimentService()
    @State private var showingImporter = false

    var body: some View {
        if speech.isSupported {
            Section("SpeechTranscriber") {
                LabeledContent("Model on this device", value: speech.isTranscriberAvailable ? "Available" : "Unavailable")
                Picker("Locale", selection: $speech.localeID) {
                    if speech.locales.isEmpty { Text("Loading…").tag("") }
                    ForEach(speech.locales) { Text($0.isInstalled ? "\($0.name) · installed" : $0.name).tag($0.id) }
                }
                .disabled(speech.isRunning)
                LabeledContent("Assets") { Text(speech.assetState.summary).multilineTextAlignment(.trailing) }
                if let progress = speech.installProgress {
                    ProgressView("Downloading model assets", value: progress)
                }
                LabeledContent("Reserved locales") {
                    Text(speech.reservedLocales.isEmpty ? "None" : speech.reservedLocales.joined(separator: ", "))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Reservation limit", value: speech.maximumReservedLocales == 0 ? "—" : "\(speech.maximumReservedLocales) locales")
                if speech.assetState == .supported {
                    Button("Download Assets", systemImage: "arrow.down.circle", action: speech.installAssets)
                        .disabled(speech.isRunning || speech.installProgress != nil)
                }
                if speech.isSelectedLocaleReserved {
                    Button("Release Reservation", systemImage: "xmark.circle", action: speech.releaseReservation)
                        .disabled(speech.isRunning)
                }
            }
            Picker("Results", selection: $speech.mode) {
                ForEach(SpeechTranscriberMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(speech.isRunning)
            controls
            TranscriptSection(speech: speech)
            Section("Audio pipeline") {
                LabeledContent("Source", value: sourceText)
                LabeledContent("Input format") { Text(speech.inputFormat).multilineTextAlignment(.trailing) }
                if speech.source == .microphone {
                    LabeledContent("Analyzer format") { Text(speech.analyzerFormat).multilineTextAlignment(.trailing) }
                    LabeledContent("Converted buffers", value: "\(speech.convertedBuffers)")
                }
                LabeledContent("Audio analyzed", value: SpeechAnalyzerFormat.timestamp(speech.audioSeconds))
            }
        }
        OutputView(text: speech.output, isError: speech.isError)
            .task { await speech.load() }
    }

    @ViewBuilder private var controls: some View {
        let ready = speech.isTranscriberAvailable && speech.selectedLocale != nil && speech.assetState != .unsupported && speech.installProgress == nil
        if speech.isRunning {
            Button(speech.isFinishing ? "Finalizing…" : "Stop", systemImage: "stop.fill", action: speech.stop)
                .buttonStyle(.borderedProminent)
                .disabled(speech.isFinishing)
                .experimentSession(speech)
        } else {
            Button("Start Live Transcription", systemImage: "mic.fill", action: speech.startLive)
                .buttonStyle(.borderedProminent)
                .disabled(!ready)
                .experimentSession(speech)
            #if !os(tvOS)
            Button("Transcribe Audio File…", systemImage: "waveform.badge.magnifyingglass") { showingImporter = true }
                .buttonStyle(.bordered)
                .disabled(!ready)
                #if canImport(UniformTypeIdentifiers)
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): if let url = urls.first { speech.transcribeFile(url) }
                    case .failure(let error): speech.reportImportFailure(error)
                    }
                }
                #endif
            #endif
        }
    }

    private var sourceText: String {
        switch speech.source {
        case .microphone: "Microphone (AVAudioEngine tap)"
        case .file(let name): name
        case nil: "—"
        }
    }
}

private struct TranscriptSection: View {
    @ObservedObject var speech: SpeechAnalyzerExperimentService

    var body: some View {
        Section("Transcript") {
            if speech.finalized.isEmpty && speech.volatileText.isEmpty {
                Text(speech.mode.reportsVolatileResults
                     ? "A greyed volatile guess appears first and is replaced by black finalized text once SpeechAnalyzer is sure."
                     : "Only finalized text is reported, so words appear in chunks after a short delay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !speech.finalized.isEmpty || !speech.volatileText.isEmpty {
                Text("\(Text(speech.transcriptText))\(Text(speech.volatileText).foregroundStyle(.secondary).italic())")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(speech.finalized) { segment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(SpeechAnalyzerFormat.timestamp(segment.start) + " – " + SpeechAnalyzerFormat.timestamp(segment.start + segment.duration))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        if let confidence = segment.confidence {
                            Text("confidence \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(.secondary)
                    Text(segment.text.trimmingCharacters(in: .whitespaces)).font(.callout)
                    ForEach(segment.alternatives, id: \.self) { alternative in
                        Text("alt: " + alternative.trimmingCharacters(in: .whitespaces)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
