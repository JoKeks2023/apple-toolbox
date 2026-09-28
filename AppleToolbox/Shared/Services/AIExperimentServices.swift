import Foundation
import Combine

#if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
import Speech
import AVFoundation
#endif

@MainActor
final class SpeechExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Speech recognition is ready."
    @Published private(set) var isRunning = false

    #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    #endif

    func start() {
        #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
        guard let recognizer, recognizer.isAvailable else { output = "Speech recognizer is not available on this device or network state."; return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            Task { @MainActor in
                PermissionCenter.shared.invalidate()
                guard authorization == .authorized else { self?.output = "Speech recognition permission was denied."; return }
                await self?.startAuthorized(recognizer: recognizer)
            }
        }
        #else
        output = "Speech recognition is not supported on this platform."
        #endif
    }

    #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
    private func startAuthorized(recognizer: SFSpeechRecognizer) async {
        do {
            let granted = await AVAudioApplication.requestRecordPermission()
            PermissionCenter.shared.invalidate()
            guard granted else { output = "Microphone permission was denied."; return }
            stop()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in request?.append(buffer) }
            audioEngine.prepare()
            try audioEngine.start()
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.output = result.bestTranscription.formattedString }
                    if let error { self?.output = "Speech recognition error: \(error.localizedDescription)"; self?.stop() }
                }
            }
            isRunning = true
            output = "Listening… speak into the microphone."
        } catch { output = "Could not start speech recognition: \(error.localizedDescription)" }
    }
    #endif

    func stop() {
        #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #endif
        isRunning = false
    }
}

enum AIAvailabilityExperimentService {
    static func coreMLStatus() -> String { "Core ML is available as a framework. A real model must be bundled or selected before inference can run; no fake model output is generated." }
    static func translationStatus() -> String { "Translation is a platform-provided workflow. A real TranslationSession and supported language pair are required; availability depends on OS and downloaded language resources." }
    static func soundAnalysisStatus() -> String { "SoundAnalysis is available for real classifier models. No bundled classifier is present yet, so the experiment reports the integration boundary instead of inventing labels." }
}
