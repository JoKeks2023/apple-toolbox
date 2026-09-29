import Foundation
import Combine
#if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
import Speech
import AVFoundation
import CoreMedia
#endif

// MARK: - Choices and results

/// Maps to SpeechTranscriber reporting and attribute options.
nonisolated enum SpeechTranscriberMode: String, CaseIterable, Identifiable, Sendable {
    case progressive = "Volatile + finalized"
    case finalOnly = "Finalized only"
    case detailed = "Volatile + alternatives + confidence"
    var id: String { rawValue }

    var reportsVolatileResults: Bool { self != .finalOnly }
}

nonisolated enum SpeechAssetState: String, Sendable {
    case unknown, unsupported, supported, downloading, installed

    var summary: String {
        switch self {
        case .unknown: "Not checked yet"
        case .unsupported: "Unsupported · no model exists for this locale on this device"
        case .supported: "Supported · model not downloaded yet"
        case .downloading: "Downloading…"
        case .installed: "Installed · transcribes on device"
        }
    }
}

nonisolated struct SpeechLocaleOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let locale: Locale
    let isInstalled: Bool
}

nonisolated struct SpeechSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let start: Double
    let duration: Double
    let confidence: Double?
    let alternatives: [String]
}

nonisolated enum SpeechAnalyzerFormat {
    /// "m:ss.s" for an offset in seconds.
    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–:––" }
        let tenths = Int((seconds * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths % 600 / 10, tenths % 10)
    }

    static func audioFormat(sampleRate: Double, channels: UInt32, sampleFormat: String, interleaved: Bool) -> String {
        "\(Int(sampleRate.rounded())) Hz · \(channels) ch · \(sampleFormat)\(interleaved ? " interleaved" : "")"
    }

    /// Output frames needed when converting `inputFrames` from `inputRate` to `outputRate`.
    static func frameCapacity(inputFrames: UInt32, inputRate: Double, outputRate: Double) -> UInt32 {
        guard inputRate > 0, outputRate > 0 else { return inputFrames }
        return UInt32((Double(inputFrames) * outputRate / inputRate).rounded(.up))
    }

    static func averageConfidence(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Service

@MainActor
final class SpeechAnalyzerExperimentService: ObservableObject {
    enum Source: Equatable {
        case microphone
        case file(String)
    }

    @Published private(set) var isTranscriberAvailable = false
    @Published private(set) var locales: [SpeechLocaleOption] = []
    @Published var localeID = "" {
        didSet { if oldValue != localeID { Task { await refreshAssetStatus() } } }
    }
    @Published var mode = SpeechTranscriberMode.progressive
    @Published private(set) var assetState = SpeechAssetState.unknown
    @Published private(set) var reservedLocales: [String] = []
    @Published private(set) var maximumReservedLocales = 0
    @Published private(set) var installProgress: Double?
    @Published private(set) var finalized: [SpeechSegment] = []
    @Published private(set) var volatileText = ""
    @Published private(set) var source: Source?
    @Published private(set) var isRunning = false
    @Published private(set) var isFinishing = false
    @Published private(set) var inputFormat = "—"
    @Published private(set) var analyzerFormat = "—"
    @Published private(set) var convertedBuffers = 0
    @Published private(set) var audioSeconds = 0.0
    @Published private(set) var output = "Loading the locales SpeechTranscriber supports…"
    @Published private(set) var isError = false

    #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var converter: SpeechBufferConverter?
    private var resultsTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    #endif

    var isSupported: Bool {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    var selectedLocale: SpeechLocaleOption? { locales.first { $0.id == localeID } }
    var isSelectedLocaleReserved: Bool { reservedLocales.contains(localeID) }
    var transcriptText: String { finalized.map(\.text).joined() }

    func load() async {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard locales.isEmpty else { return }
        isTranscriberAvailable = SpeechTranscriber.isAvailable
        let supported = await SpeechTranscriber.supportedLocales
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        locales = supported.map { locale in
            let id = locale.identifier(.bcp47)
            return SpeechLocaleOption(id: id, name: Locale.current.localizedString(forIdentifier: locale.identifier) ?? id, locale: locale, isInstalled: installed.contains(id))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        maximumReservedLocales = AssetInventory.maximumReservedLocales
        guard isTranscriberAvailable else {
            setOutput("SpeechTranscriber.isAvailable is false: this device's hardware cannot run the SpeechTranscriber model. Apple points to DictationTranscriber for such devices.", error: true)
            return
        }
        guard !locales.isEmpty else {
            setOutput("SpeechTranscriber reports no supported locales on this device.", error: true)
            return
        }
        let preferred = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)?.identifier(.bcp47)
        localeID = locales.first { $0.id == preferred }?.id ?? locales.first { $0.id.hasPrefix("en") }?.id ?? locales[0].id
        setOutput("\(locales.count) locales supported, \(installed.count) installed. Start live transcription or pick an audio file.", error: false)
        #else
        setOutput("SpeechAnalyzer needs iOS, iPadOS or macOS 26 with a microphone or file picker.", error: true)
        #endif
    }

    func refreshAssetStatus() async {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard let option = selectedLocale else { return }
        let status = await AssetInventory.status(forModules: [makeTranscriber(option.locale)])
        guard option.id == localeID else { return } // The selection changed meanwhile.
        assetState = switch status {
        case .unsupported: .unsupported
        case .supported: .supported
        case .downloading: .downloading
        case .installed: .installed
        @unknown default: .unknown
        }
        reservedLocales = await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) }
        #endif
    }

    func installAssets() {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard let option = selectedLocale, installProgress == nil, !isRunning else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureAssets(for: self.makeTranscriber(option.locale), localeName: option.name)
                self.setOutput("Assets for \(option.name) are installed.", error: false)
            } catch {
                self.setOutput("Asset installation failed: \(Self.describe(error))", error: true)
            }
            self.runTask = nil
        }
        #endif
    }

    func releaseReservation() {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard let option = selectedLocale else { return }
        Task { [weak self] in
            let released = await AssetInventory.release(reservedLocale: option.locale)
            self?.setOutput(released ? "Released the reservation for \(option.name). The system removes unused assets later." : "\(option.name) was not reserved by this app.", error: false)
            await self?.refreshAssetStatus()
        }
        #endif
    }

    func startLive() {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isRunning, installProgress == nil, let option = selectedLocale else { return }
        begin(.microphone)
        runTask = Task { [weak self] in await self?.runLive(option) }
        #endif
    }

    func transcribeFile(_ url: URL) {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isRunning, installProgress == nil, let option = selectedLocale else { return }
        begin(.file(url.lastPathComponent))
        runTask = Task { [weak self] in await self?.runFile(url, option: option) }
        #endif
    }

    func reportImportFailure(_ error: Error) {
        setOutput("File import error: \(error.localizedDescription)", error: true)
    }

    /// Live: ends the input and lets the analyzer finalize the volatile text. File: cancels the analysis.
    func stop() {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isRunning, !isFinishing else { return }
        guard let analyzer else {
            // Still downloading assets or preparing: nothing has been analyzed yet.
            runTask?.cancel()
            return finishRun("Stopped before transcription started.")
        }
        if source == .microphone {
            stopAudioInput()
            isFinishing = true
            setOutput("Finalizing the volatile results…", error: false)
            let results = resultsTask
            Task { [weak self] in
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
                await results?.value
                guard let self else { return }
                let seconds = self.audioSeconds.formatted(.number.precision(.fractionLength(1)))
                self.finishRun("Stopped. SpeechAnalyzer finalized \(self.finalized.count) segment(s) from \(seconds) s of microphone audio.")
            }
        } else {
            runTask?.cancel()
            Task { [weak self] in
                await analyzer.cancelAndFinishNow()
                self?.finishRun("File transcription cancelled.")
            }
        }
        #endif
    }

    private func begin(_ source: Source) {
        self.source = source
        isRunning = true
        isFinishing = false
        finalized = []
        volatileText = ""
        convertedBuffers = 0
        audioSeconds = 0
        inputFormat = "—"
        analyzerFormat = "—"
    }

    private func finishRun(_ message: String, error: Bool = false) {
        guard isRunning else { return }
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        if source == .microphone { stopAudioInput() }
        analyzer = nil
        converter = nil
        runTask = nil
        #endif
        isRunning = false
        isFinishing = false
        setOutput(message, error: error)
        Task { await refreshAssetStatus() }
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        switch mode {
        case .progressive:
            SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
        case .finalOnly:
            SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        case .detailed:
            SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .alternativeTranscriptions], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        }
    }

    /// Downloads the model for the transcriber's configuration unless it is already installed.
    private func ensureAssets(for transcriber: SpeechTranscriber, localeName: String) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            assetState = .installed
            return
        }
        setOutput("Downloading the \(localeName) speech model with AssetInstallationRequest…", error: false)
        assetState = .downloading
        installProgress = 0
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                self?.installProgress = request.progress.fractionCompleted
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer {
            poll.cancel()
            installProgress = nil
        }
        try await request.downloadAndInstall()
        await refreshAssetStatus()
    }

    private func runLive(_ option: SpeechLocaleOption) async {
        let granted = await AVAudioApplication.requestRecordPermission()
        PermissionCenter.shared.invalidate()
        guard granted else { return finishRun("Microphone permission was denied. Allow it in Settings › Privacy & Security › Microphone.", error: true) }
        do {
            let transcriber = makeTranscriber(option.locale)
            try await ensureAssets(for: transcriber, localeName: option.name)
            guard isRunning, !Task.isCancelled else { return }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                return finishRun("SpeechAnalyzer.bestAvailableAudioFormat returned nil for this transcriber.", error: true)
            }
            try AudioSessionController.activateForRecording()
            let input = engine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                AudioSessionController.deactivate()
                return finishRun("No audio input is available right now.", error: true)
            }
            inputFormat = Self.describe(micFormat)
            analyzerFormat = Self.describe(format)
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let converter = try SpeechBufferConverter(from: micFormat, to: format, continuation: continuation) { @Sendable [weak self] count, seconds in
                Task { @MainActor in
                    self?.convertedBuffers = count
                    self?.audioSeconds = seconds
                }
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            self.converter = converter
            observe(transcriber)
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
            guard isRunning else { return }
            input.installTap(onBus: 0, bufferSize: 4_096, format: micFormat, block: Self.makeTap(converter))
            engine.prepare()
            try engine.start()
            setOutput("Listening in \(option.name)… Grey text is volatile and may still change; black text is finalized.", error: false)
        } catch {
            finishRun("Could not start live transcription: \(Self.describe(error))", error: true)
        }
    }

    private func runFile(_ url: URL, option: SpeechLocaleOption) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let transcriber = makeTranscriber(option.locale)
            try await ensureAssets(for: transcriber, localeName: option.name)
            guard isRunning, !Task.isCancelled else { return }
            let info = try await Self.fileInfo(url)
            inputFormat = info.format
            setOutput("Transcribing \(url.lastPathComponent) (\(SpeechAnalyzerFormat.timestamp(info.duration))) in \(option.name)…", error: false)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            observe(transcriber)
            let started = ContinuousClock.now
            try await Self.analyzeFile(url, with: analyzer)
            await resultsTask?.value
            guard isRunning, !Task.isCancelled else { return }
            audioSeconds = info.duration
            let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
            finishRun("Transcribed \(SpeechAnalyzerFormat.timestamp(info.duration)) of audio in \(elapsed) into \(finalized.count) finalized segment(s).")
        } catch {
            guard isRunning, !Task.isCancelled else { return }
            finishRun("File transcription failed: \(Self.describe(error))", error: true)
        }
    }

    private func observe(_ transcriber: SpeechTranscriber) {
        resultsTask?.cancel()
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.apply(result)
                }
            } catch {
                guard let self, self.isRunning, !Task.isCancelled else { return }
                self.finishRun("SpeechTranscriber results failed: \(Self.describe(error))", error: true)
            }
        }
    }

    private func apply(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        guard result.isFinal else {
            volatileText = text
            return
        }
        let confidences = result.text.runs.compactMap { $0.transcriptionConfidence }
        let alternatives = result.alternatives.map { String($0.characters) }.filter { $0 != text }
        finalized.append(SpeechSegment(id: finalized.count, text: text, start: result.range.start.seconds, duration: result.range.duration.seconds,
                                       confidence: SpeechAnalyzerFormat.averageConfidence(confidences), alternatives: alternatives))
        volatileText = ""
    }

    private func stopAudioInput() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
            AudioSessionController.deactivate()
        }
        converter?.finish()
    }

    /// Built outside the main actor: the tap runs on the audio render thread and only hands the buffer to the converter's queue.
    nonisolated private static func makeTap(_ converter: SpeechBufferConverter) -> AVAudioNodeTapBlock {
        { buffer, _ in converter.enqueue(buffer) }
    }

    /// Reads the file's format off the main actor; AVAudioFile never reaches the main actor.
    @concurrent nonisolated private static func fileInfo(_ url: URL) async throws -> (duration: Double, format: String) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        return (Double(file.length) / format.sampleRate, describe(format))
    }

    @concurrent nonisolated private static func analyzeFile(_ url: URL, with analyzer: SpeechAnalyzer) async throws {
        let file = try AVAudioFile(forReading: url)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    nonisolated private static func describe(_ format: AVAudioFormat) -> String {
        let sampleFormat = switch format.commonFormat {
        case .pcmFormatFloat32: "Float32"
        case .pcmFormatFloat64: "Float64"
        case .pcmFormatInt16: "Int16"
        case .pcmFormatInt32: "Int32"
        default: "other"
        }
        return SpeechAnalyzerFormat.audioFormat(sampleRate: format.sampleRate, channels: format.channelCount, sampleFormat: sampleFormat, interleaved: format.isInterleaved)
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == SFSpeechErrorDomain, let name = speechErrorName(nsError.code) else { return error.localizedDescription }
        return "\(error.localizedDescription) (SFSpeechError.\(name))"
    }

    nonisolated private static func speechErrorName(_ code: Int) -> String? {
        let names: [(SFSpeechError.Code, String)] = [
            (.internalServiceError, "internalServiceError"), (.audioReadFailed, "audioReadFailed"), (.timeout, "timeout"),
            (.missingParameter, "missingParameter"), (.audioDisordered, "audioDisordered"), (.unexpectedAudioFormat, "unexpectedAudioFormat"),
            (.noModel, "noModel"), (.assetLocaleNotAllocated, "assetLocaleNotAllocated"), (.tooManyAssetLocalesAllocated, "tooManyAssetLocalesAllocated"),
            (.incompatibleAudioFormats, "incompatibleAudioFormats"), (.moduleOutputFailed, "moduleOutputFailed"),
            (.cannotAllocateUnsupportedLocale, "cannotAllocateUnsupportedLocale"), (.insufficientResources, "insufficientResources"),
        ]
        return names.first { $0.0.rawValue == code }?.1
    }
    #endif
}

#if !os(watchOS)
extension SpeechAnalyzerExperimentService: StoppableExperiment {
    var isActive: Bool { isRunning }
}
#endif

#if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
/// Converts microphone buffers to the analyzer's format on its own serial queue (never on the main actor or the
/// render thread) and feeds them into the analyzer's input stream. All mutable state is confined to `queue`.
nonisolated final class SpeechBufferConverter: @unchecked Sendable {
    enum ConversionError: LocalizedError {
        case unsupportedConversion(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedConversion(let detail): "AVAudioConverter cannot convert \(detail)."
            }
        }
    }

    private let queue = DispatchQueue(label: "apple-toolbox.speech-analyzer.convert", qos: .userInitiated)
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let progress: @Sendable (Int, Double) -> Void
    private var bufferCount = 0
    private var seconds = 0.0

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation,
         progress: @escaping @Sendable (Int, Double) -> Void) throws {
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw ConversionError.unsupportedConversion("\(inputFormat) → \(outputFormat)")
            }
            converter.primeMethod = .none // No priming frames, so timestamps stay aligned with the input.
            self.converter = converter
        }
        self.outputFormat = outputFormat
        self.continuation = continuation
        self.progress = progress
    }

    /// Called from the audio tap; the engine does not reuse a tap buffer once it has been handed out.
    func enqueue(_ buffer: AVAudioPCMBuffer) {
        nonisolated(unsafe) let buffer = buffer
        queue.async { self.convertAndYield(buffer) }
    }

    /// Ends the input sequence after every queued buffer has been delivered.
    func finish() {
        queue.async { self.continuation.finish() }
    }

    private func convertAndYield(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer), converted.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
        bufferCount += 1
        seconds += Double(converted.frameLength) / outputFormat.sampleRate
        progress(bufferCount, seconds)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let capacity = SpeechAnalyzerFormat.frameCapacity(inputFrames: buffer.frameLength, inputRate: buffer.format.sampleRate, outputRate: outputFormat.sampleRate)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(capacity)) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
#endif

extension ExperimentAvailability {
    /// SpeechTranscriber's hardware support; file transcription works without the microphone, so only a denial is reported.
    static func speechAnalyzer() -> ExperimentStatus {
        #if canImport(Speech) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard SpeechTranscriber.isAvailable else { return .hardwareUnsupported }
        let microphone = PermissionProbe.microphone()
        return microphone == .denied || microphone == .restricted ? .permissionDenied : .available
        #else
        return .platformUnsupported
        #endif
    }
}
