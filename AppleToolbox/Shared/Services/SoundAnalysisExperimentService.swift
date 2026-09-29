import Foundation
import Combine
#if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
import SoundAnalysis
import AVFoundation
#endif

nonisolated struct SoundLabel: Identifiable, Equatable, Sendable {
    let id: String
    let confidence: Double
    var name: String { id.replacingOccurrences(of: "_", with: " ").capitalized }
}

@MainActor
final class SoundAnalysisExperimentService: ObservableObject {
    @Published private(set) var output = "Live sound classification is ready."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var topLabels: [SoundLabel] = []
    @Published private(set) var classifierInfo = ""
    @Published private(set) var resultCount = 0
    /// True from the session activation until the engine runs, so leaving the experiment still stops a start in flight.
    private(set) var isStarting = false
    /// Bumped by stop(): a start that resumes after its awaits with an older value gives up.
    private var generation = 0
    #if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "apple-toolbox.sound-analysis")
    private var analyzer: SNAudioStreamAnalyzer?
    /// The analyzer does not keep its observer alive.
    private var observer: SoundClassificationObserver?
    #endif

    func start() {
        #if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isRunning, !isStarting else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.start() } else { self?.status = .permissionDenied; self?.output = "Microphone permission was denied in Settings." }
                }
            }
            return
        }
        isStarting = true
        generation += 1
        let generation = generation
        Task { await start(generation: generation) }
        #else
        status = .platformUnsupported
        output = "Live sound classification needs microphone input, which is only available on iOS, iPadOS and macOS here."
        #endif
    }

    #if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func start(generation: Int) async {
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try await AudioSessionController.activateForRecording()
            // Stopped during activation: stop() already enqueued the deactivation.
            guard generation == self.generation else { return }
            let observer = SoundClassificationObserver(
                onResult: { [weak self] labels in Task { @MainActor in self?.publish(labels) } },
                onFailure: { [weak self] message in Task { @MainActor in self?.fail(message) } })
            // The analyzer, request and observer are not Sendable: they are handed to the audio queue and not
            // touched here until the start has finished.
            let engine = engine
            nonisolated(unsafe) let queueRequest = request
            nonisolated(unsafe) let queueObserver = observer
            nonisolated(unsafe) var created: SNAudioStreamAnalyzer?
            let analysisQueue = analysisQueue
            try await AudioSessionController.perform {
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { return }
                let analyzer = SNAudioStreamAnalyzer(format: format)
                try analyzer.add(queueRequest, withObserver: queueObserver)
                input.installTap(onBus: 0, bufferSize: 8_192, format: format, block: Self.makeTap(analyzer: analyzer, queue: analysisQueue))
                engine.prepare()
                do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
                created = analyzer
            }
            // Stopped while starting: stop() enqueued the engine stop after this start.
            guard generation == self.generation else { return }
            isStarting = false
            guard let analyzer = created else {
                AudioSessionController.deactivate()
                status = .hardwareUnsupported
                output = "No audio input is available right now."
                return
            }
            self.analyzer = analyzer
            self.observer = observer
            topLabels = []
            resultCount = 0
            classifierInfo = "\(request.knownClassifications.count) known sounds · \(request.windowDuration.seconds.formatted(.number.precision(.fractionLength(1)))) s window"
            isRunning = true
            status = .available
            output = "Listening… Sound Analysis classifies the microphone stream on a background queue."
        } catch {
            guard generation == self.generation else { return }
            isStarting = false
            AudioSessionController.deactivate()
            status = .unavailable
            output = "Could not start sound analysis: \(error.localizedDescription)"
        }
    }
    #endif

    func stop() {
        let wasActive = isRunning || isStarting
        generation += 1
        isStarting = false
        #if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        let engine = engine // Only touched on the audio queue.
        AudioSessionController.enqueue {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if let analyzer {
            nonisolated(unsafe) let analyzer = analyzer // Only ever used on analysisQueue.
            analysisQueue.async { analyzer.removeAllRequests() }
        }
        analyzer = nil
        observer = nil
        if wasActive { AudioSessionController.deactivate() }
        #endif
        if isRunning { output = "Sound analysis stopped after \(resultCount) classification result(s)." }
        isRunning = false
    }

    private func publish(_ labels: [SoundLabel]) {
        guard isRunning else { return } // Results can still arrive from the queue after stop().
        topLabels = labels
        resultCount += 1
    }

    private func fail(_ message: String) {
        guard isRunning else { return }
        stop()
        status = .unavailable
        output = "Sound analysis error: \(message)"
    }

    #if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    /// Built outside the main actor: the tap runs on the audio thread and only hands buffers to the analysis queue.
    /// The analyzer is only touched on that serial queue and each tap buffer is handed over, never reused here.
    nonisolated private static func makeTap(analyzer: SNAudioStreamAnalyzer, queue: DispatchQueue) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let analyzer = analyzer
        return { buffer, time in
            nonisolated(unsafe) let buffer = buffer
            queue.async { analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime) }
        }
    }
    #endif
}

extension SoundAnalysisExperimentService: StoppableExperiment { var isActive: Bool { isRunning || isStarting } }

#if canImport(SoundAnalysis) && canImport(AVFoundation) && (os(iOS) || os(macOS))
/// Receives results on the analysis queue and forwards only Sendable values.
nonisolated private final class SoundClassificationObserver: NSObject, SNResultsObserving {
    private let onResult: @Sendable ([SoundLabel]) -> Void
    private let onFailure: @Sendable (String) -> Void

    init(onResult: @escaping @Sendable ([SoundLabel]) -> Void, onFailure: @escaping @Sendable (String) -> Void) {
        self.onResult = onResult
        self.onFailure = onFailure
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let top = result.classifications.sorted { $0.confidence > $1.confidence }.prefix(3)
        onResult(top.map { SoundLabel(id: $0.identifier, confidence: $0.confidence) })
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        onFailure(error.localizedDescription)
    }
}
#endif
