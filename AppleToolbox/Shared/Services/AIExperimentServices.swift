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
    /// True from the session activation until the engine runs, so leaving the experiment still stops a start in flight.
    private(set) var isStarting = false
    /// Bumped by stop(): a start that resumes after its awaits with an older value gives up.
    private var generation = 0

    #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Set once the recording session is active, so a failed start still deactivates it.
    private var isAudioSessionActive = false
    #endif

    func start() {
        #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
        guard let recognizer, recognizer.isAvailable else { output = "Speech recognizer is not available on this device or network state."; return }
        SFSpeechRecognizer.requestAuthorization { @Sendable [weak self] authorization in
            Task { @MainActor in
                PermissionCenter.shared.invalidate()
                guard let self else { return }
                guard authorization == .authorized else { self.output = "Speech recognition permission was denied."; return }
                guard let recognizer = self.recognizer else { return }
                await self.startAuthorized(recognizer: recognizer)
            }
        }
        #else
        output = "Speech recognition is not supported on this platform."
        #endif
    }

    #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
    private func startAuthorized(recognizer: SFSpeechRecognizer) async {
        let granted = await AVAudioApplication.requestRecordPermission()
        PermissionCenter.shared.invalidate()
        guard granted else { output = "Microphone permission was denied."; return }
        stop()
        let generation = generation
        isStarting = true
        do {
            // Set before the await: a stop() meanwhile enqueues its deactivation after this activation.
            isAudioSessionActive = true
            try await AudioSessionController.activateForRecording()
            guard generation == self.generation else { return }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let engine = audioEngine // Only touched on the audio queue.
            nonisolated(unsafe) let tapRequest = request // append(_:) is designed to be called from the audio tap.
            let hasInput = try await AudioSessionController.perform { () throws -> Bool in
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { return false }
                input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable buffer, _ in tapRequest.append(buffer) }
                engine.prepare()
                do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
                return true
            }
            // Stopped while starting: stop() enqueued the engine stop after this start.
            guard generation == self.generation else { return }
            isStarting = false
            guard hasInput else {
                stop()
                output = "No audio input is available right now."
                return
            }
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.isRunning else { return } // Ignore the cancellation that follows stop().
                    if let result { self.output = result.bestTranscription.formattedString }
                    if let error { self.output = "Speech recognition error: \(error.localizedDescription)"; self.stop() }
                }
            }
            isRunning = true
            output = "Listening… speak into the microphone."
        } catch {
            guard generation == self.generation else { return }
            stop()
            output = "Could not start speech recognition: \(error.localizedDescription)"
        }
    }
    #endif

    func stop() {
        #if canImport(Speech) && canImport(AVFoundation) && !os(watchOS) && !os(tvOS)
        generation += 1
        isStarting = false
        let engine = audioEngine // Only touched on the audio queue.
        AudioSessionController.enqueue {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if isAudioSessionActive {
            AudioSessionController.deactivate()
            isAudioSessionActive = false
        }
        #endif
        isRunning = false
    }
}
