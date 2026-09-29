import Foundation
import Combine

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#if canImport(Vision)
import Vision
#endif
#endif

@MainActor
final class AudioExperimentService: ObservableObject {
    @Published private(set) var output = "Microphone input is ready."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var rmsLevel: Double = 0
    @Published private(set) var peakLevel: Double = 0
    @Published private(set) var levelHistory: [Double] = []
    @Published private(set) var channelCount = 0
    @Published private(set) var sampleRate = 0
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private let engine = AVAudioEngine()
    #endif

    func start() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
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
        do { try AudioSessionController.activateForRecording() }
        catch { output = "Audio session error: \(error.localizedDescription)"; status = .unavailable; return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            AudioSessionController.deactivate()
            output = "No audio input is available right now."
            status = .hardwareUnsupported
            return
        }
        channelCount = Int(format.channelCount)
        sampleRate = Int(format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            var peak: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
            for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[index])) }
            let rms = sqrt(sum / Float(buffer.frameLength))
            Task { @MainActor in
                self?.rmsLevel = Double(rms)
                self?.peakLevel = Double(peak)
                self?.levelHistory = Array(((self?.levelHistory ?? []) + [Double(peak)]).suffix(48))
                self?.output = "Live microphone input is updating."
            }
        }
        do { try engine.start(); isRunning = true; status = .available }
        catch { input.removeTap(onBus: 0); AudioSessionController.deactivate(); output = "Audio engine error: \(error.localizedDescription)"; status = .unavailable }
        #else
        status = .platformUnsupported
        output = "Audio input is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        AudioSessionController.deactivate()
        #endif
        isRunning = false
        output = "Audio input stopped."
    }
}
