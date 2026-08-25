import Foundation
import Combine

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#if canImport(Vision)
import Vision
#endif
#endif

@MainActor
final class CameraVisionExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Camera and Vision are ready."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "apple-toolbox.camera")
    #endif

    func start() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.start() } else { self?.status = .permissionDenied; self?.output = "Camera permission was denied in Settings." }
                }
            }
            return
        }
        guard let device = AVCaptureDevice.default(for: .video) else { status = .hardwareUnsupported; output = "No camera is available on this device."; return }
        do {
            session.beginConfiguration()
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(videoOutput) else { throw ExperimentServiceError.unavailable("Camera session cannot accept the required input/output.") }
            session.addInput(input)
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
            session.commitConfiguration()
            session.startRunning()
            isRunning = true
            status = .available
            output = "Camera running. Vision will inspect incoming frames for text."
        } catch { session.commitConfiguration(); output = "Camera error: \(error.localizedDescription)"; status = .unavailable }
        #else
        status = .platformUnsupported
        output = "Camera capture is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        session.stopRunning()
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        #endif
        isRunning = false
        output = "Camera and Vision stopped."
    }
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS)) && canImport(Vision)
extension CameraVisionExperimentService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.prefix(5).joined(separator: "\n")
            Task { @MainActor in
                if let error { self?.output = "Vision error: \(error.localizedDescription)" }
                else { self?.output = text.isEmpty ? "Camera running. No text detected in the latest frame." : "Detected text:\n\(text)" }
            }
        }
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform([request])
    }
}
#endif

@MainActor
final class AudioExperimentService: ObservableObject {
    @Published private(set) var output = "Microphone input is ready."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    private let engine = AVAudioEngine()
    #endif

    func start() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.start() } else { self?.status = .permissionDenied; self?.output = "Microphone permission was denied in Settings." }
                }
            }
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            Task { @MainActor in self?.output = "Input channels: \(buffer.format.channelCount)\nSample rate: \(Int(buffer.format.sampleRate)) Hz\nRMS level: \(rms.formatted(.number.precision(.fractionLength(4))))" }
        }
        do { try engine.start(); isRunning = true; status = .available }
        catch { input.removeTap(onBus: 0); output = "Audio engine error: \(error.localizedDescription)"; status = .unavailable }
        #else
        status = .platformUnsupported
        output = "Audio input is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #endif
        isRunning = false
        output = "Audio input stopped."
    }
}
