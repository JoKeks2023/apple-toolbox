import Foundation
import Combine

struct VisionTextResult: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let confidence: Double
}

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
    @Published private(set) var detectedTexts: [VisionTextResult] = []
    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    // All session configuration, start and stop run on the serial sessionQueue, as Apple recommends
    // (startRunning blocks until the camera is running). The queue serializes access to these objects.
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "apple-toolbox.camera.session")
    private let frameQueue = DispatchQueue(label: "apple-toolbox.camera.frames")
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    #endif

    func start() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isRunning else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.start() } else { self?.status = .permissionDenied; self?.output = "Camera permission was denied in Settings." }
                }
            }
            return
        }
        guard let device = AVCaptureDevice.default(for: .video) else { status = .hardwareUnsupported; output = "No camera is available on this device."; return }
        isRunning = true
        status = .available
        detectedTexts.removeAll()
        output = "Starting camera…"
        followDeviceRotation(of: device)
        nonisolated(unsafe) let captureDevice = device // Only used on sessionQueue from here on.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let failure = configureAndStart(device: captureDevice)
            Task { @MainActor in
                if let failure {
                    self.stop()
                    self.output = "Camera error: \(failure)"
                    self.status = .unavailable
                } else {
                    self.output = "Camera running. Vision will inspect incoming frames for text."
                }
            }
        }
        #else
        status = .platformUnsupported
        output = "Camera capture is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        rotationObservation = nil
        rotationCoordinator = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.stopRunning()
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            // Remove input and output so the next start can add them again.
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
        }
        #endif
        isRunning = false
        output = "Camera and Vision stopped."
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    /// Runs on sessionQueue; returns an error description or nil when the session is running.
    nonisolated private func configureAndStart(device: AVCaptureDevice) -> String? {
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return "Camera session cannot accept the required input/output."
            }
            session.addInput(input)
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            session.addOutput(videoOutput)
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            return error.localizedDescription
        }
        session.startRunning()
        return nil
    }

    /// Rotates delivered frames so they are upright for Vision, following the device orientation.
    private func followDeviceRotation(of device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in self?.applyRotation(angle) }
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let connection = self?.videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
    #endif
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS)) && canImport(Vision)
extension CameraVisionExperimentService: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Runs on frameQueue. Vision works synchronously here, so late frames are dropped while a frame is analyzed.
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let results = observations.compactMap { observation -> VisionTextResult? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return VisionTextResult(text: candidate.string, confidence: Double(candidate.confidence))
            }.prefix(8)
            let text = results.map(\.text).joined(separator: "\n")
            Task { @MainActor in
                if let error { self?.output = "Vision error: \(error.localizedDescription)" }
                else {
                    self?.detectedTexts = Array(results)
                    self?.output = text.isEmpty ? "Camera running. No text detected in the latest frame." : "Detected \(results.count) text item(s) in the latest frame."
                }
            }
        }
        request.recognitionLevel = VNRequestTextRecognitionLevel.fast
        request.usesLanguageCorrection = false
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Frames are already rotated upright through the connection's rotation angle.
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
    }
}
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
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
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
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
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
