import Foundation
import Combine
import CoreGraphics
import CoreVideo
import ImageIO
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
import CoreMedia
#endif

// MARK: - Choices and snapshots (Sendable, created on the capture queues)

nonisolated enum CameraCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case photo = "Photo"
    case video = "Video"
    var id: String { rawValue }
}

nonisolated enum CameraFocusBehavior: String, CaseIterable, Identifiable, Sendable {
    case continuous = "Continuous auto focus"
    case single = "Auto focus once"
    case locked = "Locked"
    var id: String { rawValue }
}

nonisolated enum CameraPhotoCodec: String, CaseIterable, Identifiable, Sendable {
    case hevc = "HEIC (HEVC)"
    case jpeg = "JPEG"
    var id: String { rawValue }
}

nonisolated enum CameraFlashSetting: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case auto = "Auto"
    case on = "On"
    var id: String { rawValue }
}

nonisolated enum CameraHDRSetting: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case on = "On"
    case off = "Off"
    var id: String { rawValue }
}

nonisolated struct CameraDeviceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let position: String
}

nonisolated struct CameraMetadataRow: Identifiable, Hashable, Sendable {
    let title: String
    let value: String
    var id: String { title }
}

/// Everything the lab shows about the running camera, read on the session queue.
nonisolated struct CameraDeviceState: Equatable, Sendable {
    var deviceName = ""
    var typeName = ""
    var position = ""
    var activeFormat = ""
    var isVirtual = false
    var constituents: [String] = []
    var switchOverZoomFactors: [Double] = []
    var focusModes: [CameraFocusBehavior] = []
    var focus: CameraFocusBehavior?
    var supportsFocusPoint = false
    var supportsExposurePoint = false
    var isAdjustingFocus = false
    var isAdjustingExposure = false
    var lensPosition: Float?
    var iso: Float?
    var exposureDuration: Double?
    var exposureBias: Float = 0
    var exposureBiasRange: ClosedRange<Float>?
    var zoom: Double = 1
    var zoomRange: ClosedRange<Double>?
    var zoomDisplayMultiplier: Double = 1
    var hasTorch = false
    var torchAvailable = false
    var torchOn = false
    var hasFlash = false
    var hdrSupported = false
    var hdrEnabled = false
    var hdrAutomatic = true
    var lensAperture: Float?
    var fieldOfView: Float?
    var minimumFocusDistance: Int?
    var depthFormats: [String] = []
    var activeDepthFormat: String?
    var photoCodecs: [CameraPhotoCodec] = []
    var flashModes: [CameraFlashSetting] = []
    var maxPhotoDimensions: String?
    var depthDeliverySupported = false
    var depthDeliveryEnabled = false
    var hasPhotoOutput = false
    var hasMovieOutput = false
    var hasAudioInput = false
}

nonisolated struct CameraCapturedPhoto: Sendable {
    let image: CGImage?
    let fileURL: URL
    let byteCount: Int
    let dimensions: String
    let metadata: [CameraMetadataRow]
    let depth: [CameraMetadataRow]
}

nonisolated struct CameraRecordedMovie: Sendable {
    let fileURL: URL
    let duration: Double
    let byteCount: Int64
    let hasAudio: Bool
}

nonisolated struct CameraLabError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Formatting (pure, unit tested)

nonisolated enum CameraLabFormat {
    /// "1/120 s" for short exposures, "1.5 s" for long ones.
    static func exposure(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds >= 1 { return String(format: "%.1f s", seconds) }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    static func aperture(_ fNumber: Double) -> String { String(format: "ƒ/%.2g", fNumber) }

    static func zoom(_ factor: Double, multiplier: Double = 1) -> String {
        let value = factor * multiplier
        return value.rounded() == value ? String(format: "%.0f×", value) : String(format: "%.1f×", value)
    }

    static func dimensions(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "—" }
        let megapixels = Double(width * height) / 1_000_000
        return String(format: "%d × %d (%.1f MP)", width, height, megapixels)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Four-character code as text, e.g. 875704422 → "420v".
    static func fourCC(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(format: "0x%08X", code) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func depthTypeName(_ pixelFormat: UInt32) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_DisparityFloat16: "Disparity, Float16"
        case kCVPixelFormatType_DisparityFloat32: "Disparity, Float32"
        case kCVPixelFormatType_DepthFloat16: "Depth (m), Float16"
        case kCVPixelFormatType_DepthFloat32: "Depth (m), Float32"
        default: fourCC(pixelFormat)
        }
    }

    static func orientationName(_ value: Int) -> String {
        switch value {
        case 1: "Up (1)"
        case 2: "Up, mirrored (2)"
        case 3: "Down (3)"
        case 4: "Down, mirrored (4)"
        case 5: "Left, mirrored (5)"
        case 6: "Right (6)"
        case 7: "Right, mirrored (7)"
        case 8: "Left (8)"
        default: "\(value)"
        }
    }

    /// Readable EXIF/TIFF rows from `AVCapturePhoto.metadata` (the same dictionary ImageIO writes into the file).
    static func metadataRows(_ metadata: [String: Any]) -> [CameraMetadataRow] {
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        var rows: [CameraMetadataRow] = []
        func add(_ title: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append(CameraMetadataRow(title: title, value: value)) }
        }
        let camera = [tiff[kCGImagePropertyTIFFMake as String] as? String, tiff[kCGImagePropertyTIFFModel as String] as? String].compactMap { $0 }
        add("Camera", camera.joined(separator: " "))
        add("Lens", exif[kCGImagePropertyExifLensModel as String] as? String)
        add("Exposure", (exif[kCGImagePropertyExifExposureTime as String] as? Double).map(exposure))
        add("Aperture", (exif[kCGImagePropertyExifFNumber as String] as? Double).map(aperture))
        add("ISO", (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first.map { "ISO \($0)" })
        if let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double {
            let equivalent = (exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int).map { " (\($0) mm equiv.)" } ?? ""
            add("Focal length", String(format: "%.2f mm", focal) + equivalent)
        }
        add("Exposure bias", (exif[kCGImagePropertyExifExposureBiasValue as String] as? Double).map { String(format: "%+.1f EV", $0) })
        add("Brightness", (exif[kCGImagePropertyExifBrightnessValue as String] as? Double).map { String(format: "%.2f EV", $0) })
        add("Flash", (exif[kCGImagePropertyExifFlash as String] as? Int).map { $0 & 1 == 1 ? "Fired" : "Did not fire" })
        add("White balance", (exif[kCGImagePropertyExifWhiteBalance as String] as? Int).map { $0 == 0 ? "Auto" : "Manual" })
        add("Captured", exif[kCGImagePropertyExifDateTimeOriginal as String] as? String)
        add("Software", tiff[kCGImagePropertyTIFFSoftware as String] as? String)
        add("Orientation", (metadata[kCGImagePropertyOrientation as String] as? Int).map(orientationName))
        return rows
    }
}

// MARK: - Service

/// Camera Lab: preview, device selection, photo capture with metadata and depth, controls and short video recording.
@MainActor
final class CameraLabService: ObservableObject {
    nonisolated static let maxRecordingSeconds: Double = 60

    @Published private(set) var output: String
    @Published private(set) var status: ExperimentStatus
    @Published private(set) var devices: [CameraDeviceOption] = []
    @Published private(set) var selectedDeviceID = ""
    @Published private(set) var mode: CameraCaptureMode = .photo
    @Published private(set) var isRunning = false
    @Published private(set) var isConfiguring = false
    @Published private(set) var state: CameraDeviceState?
    @Published private(set) var focusBehavior: CameraFocusBehavior = .continuous
    @Published var codec: CameraPhotoCodec = .hevc
    @Published var flash: CameraFlashSetting = .off
    @Published private(set) var deliversDepth = false
    @Published private(set) var recordsAudio = false
    @Published private(set) var isCapturingPhoto = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var lastPhoto: CameraCapturedPhoto?
    @Published private(set) var lastMovie: CameraRecordedMovie?
    /// Last tap on the preview in view coordinates, shown as a focus marker.
    @Published private(set) var focusMarker: CGPoint?

    var isRecording: Bool { recordingStartedAt != nil }
    var isActive: Bool { isRunning || isConfiguring || isRecording }
    var isError: Bool { [.unavailable, .permissionDenied, .hardwareUnsupported, .platformUnsupported].contains(status) }

    /// Discards results of a configuration that finished after the camera was stopped.
    private var generation = 0
    private var pollTask: Task<Void, Never>?

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    // All session configuration, start and stop run on the serial sessionQueue, as Apple recommends
    // (startRunning blocks). The queue serializes access to these capture objects; the preview layer
    // only receives `session` on the main thread, as in Apple's AVCam sample.
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    nonisolated private let captureDelegate = CameraCaptureDelegate()
    private let sessionQueue = DispatchQueue(label: "apple-toolbox.camera-lab.session")
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var observers: [any NSObjectProtocol] = []
    #endif

    init() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        status = ExperimentAvailability.camera()
        output = "Pick a camera and start the preview. Nothing is captured until you tap the shutter or record."
        captureDelegate.service = self
        refreshDevices { service in
            guard service.devices.isEmpty else { return }
            service.status = .hardwareUnsupported
            service.output = "AVCaptureDevice.DiscoverySession reports no video capture device on this \(CurrentPlatform.value.rawValue) device."
        }
        #else
        status = .platformUnsupported
        output = "There is no camera capture API on \(CurrentPlatform.value.rawValue): Apple TV has no built-in camera and this lab does not cover Continuity Camera, Apple Watch has no camera."
        #endif
    }

    // MARK: Session

    func start() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isActive else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            status = .permissionRequired
            output = "Waiting for camera permission…"
            AVCaptureDevice.requestAccess(for: .video) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.start() } else { self?.reportDenied() }
                }
            }
            return
        default:
            reportDenied()
            return
        }
        let id = generation
        refreshDevices { service in
            // stop() or a second start() may have happened while the devices were discovered.
            guard id == service.generation, !service.isActive else { return }
            guard !service.selectedDeviceID.isEmpty else {
                service.status = .hardwareUnsupported
                service.output = "No camera is available on this device."
                return
            }
            service.observeSession()
            service.reconfigure(start: true)
        }
        #endif
    }

    func stop() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        rotationObservation = nil
        rotationCoordinator = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if movieOutput.isRecording { movieOutput.stopRecording() }
            session.stopRunning()
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
            videoDevice = nil
        }
        #endif
        let wasActive = isActive
        isRunning = false
        isConfiguring = false
        isCapturingPhoto = false
        recordingStartedAt = nil
        focusMarker = nil
        if wasActive { output = "Camera stopped. The session released the camera\(lastMovie == nil ? "" : " and kept the last recording")." }
    }

    func selectDevice(_ id: String) {
        guard id != selectedDeviceID, !isRecording else { return }
        selectedDeviceID = id
        if isRunning { reconfigure(start: false) }
    }

    func setMode(_ newMode: CameraCaptureMode) {
        guard newMode != mode, !isRecording else { return }
        mode = newMode
        if isRunning { reconfigure(start: false) }
    }

    func setDeliversDepth(_ enabled: Bool) {
        deliversDepth = enabled
        if isRunning, mode == .photo { reconfigure(start: false) }
    }

    func setRecordsAudio(_ enabled: Bool) {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard enabled else {
            recordsAudio = false
            if isRunning, mode == .video { reconfigure(start: false) }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            recordsAudio = true
            if isRunning, mode == .video { reconfigure(start: false) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.setRecordsAudio(true) } else { self?.output = "Microphone access was denied, so recordings stay video-only." }
                }
            }
        default:
            recordsAudio = false
            output = "Microphone access is denied or restricted, so recordings stay video-only. Allow it in Settings › Privacy & Security › Microphone."
        }
        #endif
    }

    // MARK: Controls

    func setFocusBehavior(_ behavior: CameraFocusBehavior) {
        focusBehavior = behavior
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        let mode = behavior.focusMode
        updateDevice(report: "Focus mode set to \(behavior.rawValue).") { device in
            guard device.isFocusModeSupported(mode) else { throw CameraLabError(message: "\(behavior.rawValue) is not supported by \(device.localizedName).") }
            device.focusMode = mode
        }
        #endif
    }

    /// Sets focus and exposure point of interest; `devicePoint` is in the capture device's normalized coordinates.
    func focus(atDevicePoint devicePoint: CGPoint, viewPoint: CGPoint) {
        focusMarker = viewPoint
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        let behavior = focusBehavior
        let point = String(format: "(%.2f, %.2f)", devicePoint.x, devicePoint.y)
        updateDevice(report: "Focus and exposure point of interest set to \(point) in device coordinates.") { device in
            guard device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported else {
                throw CameraLabError(message: "\(device.localizedName) supports neither a focus nor an exposure point of interest.")
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                // A tap focuses once at the point; continuous mode keeps tracking from there.
                let mode: AVCaptureDevice.FocusMode = behavior == .continuous ? .continuousAutoFocus : .autoFocus
                if device.isFocusModeSupported(mode) { device.focusMode = mode }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            }
        }
        #endif
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if focusMarker == viewPoint { focusMarker = nil }
        }
    }

    func setZoom(_ factor: Double) {
        state?.zoom = factor
        #if os(iOS)
        updateDevice { device in
            let clamped = min(max(CGFloat(factor), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clamped
        }
        #endif
    }

    func setExposureBias(_ bias: Float) {
        state?.exposureBias = bias
        #if os(iOS)
        updateDevice { device in
            device.setExposureTargetBias(min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias), completionHandler: nil)
        }
        #endif
    }

    func setTorch(_ on: Bool) {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        updateDevice(report: on ? "Torch on." : "Torch off.") { device in
            guard device.hasTorch, device.isTorchAvailable, device.isTorchModeSupported(on ? .on : .off) else {
                throw CameraLabError(message: "\(device.localizedName) has no torch available right now (isTorchAvailable is false, e.g. when the device is too hot).")
            }
            device.torchMode = on ? .on : .off
        }
        #endif
    }

    func setHDR(_ setting: CameraHDRSetting) {
        #if os(iOS)
        updateDevice(report: "Video HDR: \(setting.rawValue).") { device in
            switch setting {
            case .automatic:
                device.automaticallyAdjustsVideoHDREnabled = true
            case .on, .off:
                guard device.activeFormat.isVideoHDRSupported else {
                    throw CameraLabError(message: "The active format of \(device.localizedName) does not support video HDR.")
                }
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = setting == .on
            }
        }
        #endif
    }

    // MARK: Capture

    func capturePhoto() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isRunning, mode == .photo, !isCapturingPhoto else { return }
        isCapturingPhoto = true
        output = "Capturing photo…"
        let request = CameraPhotoRequest(codec: codec, flash: flash, depth: deliversDepth, rotation: rotationCoordinator?.videoRotationAngleForHorizonLevelCapture)
        sessionQueue.async { [weak self] in
            guard let self, let failure = requestPhoto(request) else { return }
            Task { @MainActor in
                self.isCapturingPhoto = false
                self.output = failure
            }
        }
        #endif
    }

    func toggleRecording() {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isRunning, mode == .video else { return }
        if isRecording {
            output = "Finishing the recording…"
            sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
            return
        }
        removeMovie()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CameraLab-\(Int(Date().timeIntervalSince1970)).mov")
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture
        recordingStartedAt = Date()
        output = "Recording with AVCaptureMovieFileOutput (stops automatically after \(Int(Self.maxRecordingSeconds)) s)…"
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let angle, let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            movieOutput.startRecording(to: url, recordingDelegate: captureDelegate)
        }
        #endif
    }

    // MARK: Delegate results

    fileprivate func didFinishPhoto(_ result: Result<CameraCapturedPhoto, CameraLabError>) {
        isCapturingPhoto = false
        switch result {
        case .success(let photo):
            if let old = lastPhoto?.fileURL, old != photo.fileURL { try? FileManager.default.removeItem(at: old) }
            lastPhoto = photo
            let depth = photo.depth.isEmpty ? "" : " with depth data"
            output = "Photo captured\(depth): \(photo.fileURL.pathExtension.uppercased()), \(photo.dimensions), \(ByteCountFormatter.string(fromByteCount: Int64(photo.byteCount), countStyle: .file))."
        case .failure(let error):
            output = error.message
        }
    }

    fileprivate func didFinishRecording(url: URL, error: String?, hasAudio: Bool) {
        recordingStartedAt = nil
        guard FileManager.default.fileExists(atPath: url.path) else {
            output = "Recording failed: \(error ?? "no file was written.")"
            return
        }
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        Task {
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            lastMovie = CameraRecordedMovie(fileURL: url, duration: duration, byteCount: size, hasAudio: hasAudio)
            let note = error.map { " AVFoundation reported: \($0)" } ?? ""
            output = "Recorded \(CameraLabFormat.duration(duration)) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), \(hasAudio ? "with" : "without") audio).\(note)"
        }
        #endif
    }

    private func removeMovie() {
        if let url = lastMovie?.fileURL { try? FileManager.default.removeItem(at: url) }
        lastMovie = nil
    }

    private func reportDenied() {
        status = .permissionDenied
        output = "Camera access is denied or restricted. Allow it in Settings › Privacy & Security › Camera."
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    // MARK: Preview

    var previewSession: AVCaptureSession { session }

    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        if isRunning { followRotation() }
    }

    // MARK: Internals

    /// Device discovery can block, so it runs on sessionQueue; the result is published on the main actor.
    private func refreshDevices(then completion: @escaping @MainActor (CameraLabService) -> Void = { _ in }) {
        sessionQueue.async { [weak self] in
            let found = AVCaptureDevice.DiscoverySession(deviceTypes: Self.deviceTypes, mediaType: .video, position: .unspecified).devices
            let options = found.map { CameraDeviceOption(id: $0.uniqueID, name: $0.localizedName, kind: Self.typeName($0.deviceType), position: Self.positionName($0.position)) }
            let preferred = AVCaptureDevice.default(for: .video)?.uniqueID
            Task { @MainActor in
                guard let self else { return }
                self.devices = options
                if !options.contains(where: { $0.id == self.selectedDeviceID }) {
                    self.selectedDeviceID = options.first(where: { $0.id == preferred })?.id ?? options.first?.id ?? ""
                }
                completion(self)
            }
        }
    }

    private func reconfigure(start: Bool) {
        guard let device = AVCaptureDevice(uniqueID: selectedDeviceID) else {
            output = "The selected camera is no longer connected."
            refreshDevices()
            return
        }
        generation += 1
        let id = generation
        isConfiguring = true
        output = start ? "Starting \(device.localizedName)…" : "Reconfiguring the session for \(device.localizedName) (\(mode.rawValue.lowercased()) mode)…"
        let options = CameraSessionOptions(mode: mode, depth: deliversDepth,
                                           audio: recordsAudio && mode == .video && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        nonisolated(unsafe) let video = device // Handed to sessionQueue, which owns every capture object from here on.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let result = configureSession(video: video, options: options)
            Task { @MainActor in self.finishConfiguration(result, generation: id) }
        }
    }

    private func finishConfiguration(_ result: Result<CameraDeviceState, CameraLabError>, generation id: Int) {
        guard id == generation else { return }
        isConfiguring = false
        switch result {
        case .success(let state):
            self.state = state
            isRunning = true
            status = .available
            if !state.photoCodecs.isEmpty, !state.photoCodecs.contains(codec) { codec = state.photoCodecs[0] }
            if !state.flashModes.contains(flash) { flash = .off }
            if let focus = state.focus { focusBehavior = focus }
            if deliversDepth, !state.depthDeliverySupported { deliversDepth = false }
            followRotation()
            startPolling()
            var lines = ["\(state.deviceName) running · \(state.activeFormat)."]
            if mode == .photo { lines.append(state.depthDeliverySupported ? "This configuration can deliver depth data with photos." : "This camera/format cannot deliver depth data with photos.") }
            if mode == .video { lines.append(state.hasAudioInput ? "Recordings include microphone audio." : "Recordings are video-only.") }
            output = lines.joined(separator: "\n")
        case .failure(let error):
            stop()
            status = .unavailable
            output = "Camera error: \(error.message)"
        }
    }

    /// Runs on sessionQueue: rebuilds inputs and outputs for the chosen camera and mode.
    nonisolated private func configureSession(video: AVCaptureDevice, options: CameraSessionOptions) -> Result<CameraDeviceState, CameraLabError> {
        if movieOutput.isRecording { movieOutput.stopRecording() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        let preset: AVCaptureSession.Preset = options.mode == .photo ? .photo : .high
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset }
        do {
            let input = try AVCaptureDeviceInput(device: video)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return .failure(CameraLabError(message: "The capture session cannot add \(video.localizedName) as an input."))
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            return .failure(CameraLabError(message: error.localizedDescription))
        }
        if options.audio, let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input) {
            session.addInput(input)
        }
        let output: AVCaptureOutput = options.mode == .photo ? photoOutput : movieOutput
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return .failure(CameraLabError(message: "The capture session cannot add \(options.mode == .photo ? "AVCapturePhotoOutput" : "AVCaptureMovieFileOutput") for \(video.localizedName)."))
        }
        session.addOutput(output)
        if options.mode == .photo {
            #if os(iOS)
            // Depth delivery must be enabled on the output before a photo can request it.
            photoOutput.isDepthDataDeliveryEnabled = options.depth && photoOutput.isDepthDataDeliverySupported
            #endif
        } else {
            movieOutput.maxRecordedDuration = CMTime(seconds: Self.maxRecordingSeconds, preferredTimescale: 600)
        }
        session.commitConfiguration()
        if options.mode == .photo {
            let supported = video.activeFormat.supportedMaxPhotoDimensions
            if let largest = supported.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                photoOutput.maxPhotoDimensions = largest
            }
        }
        videoDevice = video
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else { return .failure(CameraLabError(message: "AVCaptureSession did not start running.")) }
        return .success(readState(video))
    }

    /// Runs on sessionQueue.
    nonisolated private func readState(_ device: AVCaptureDevice) -> CameraDeviceState {
        var state = CameraDeviceState()
        state.deviceName = device.localizedName
        state.typeName = Self.typeName(device.deviceType)
        state.position = Self.positionName(device.position)
        state.activeFormat = Self.formatSummary(device.activeFormat)
        state.focusModes = CameraFocusBehavior.allCases.filter { device.isFocusModeSupported($0.focusMode) }
        state.focus = CameraFocusBehavior.allCases.first { $0.focusMode == device.focusMode }
        state.supportsFocusPoint = device.isFocusPointOfInterestSupported
        state.supportsExposurePoint = device.isExposurePointOfInterestSupported
        state.isAdjustingFocus = device.isAdjustingFocus
        state.isAdjustingExposure = device.isAdjustingExposure
        state.hasTorch = device.hasTorch
        state.torchAvailable = device.isTorchAvailable
        state.torchOn = device.torchMode == .on
        state.hasFlash = device.hasFlash
        state.minimumFocusDistance = device.minimumFocusDistance >= 0 ? device.minimumFocusDistance : nil
        #if os(iOS)
        state.isVirtual = device.isVirtualDevice
        state.constituents = device.constituentDevices.map(\.localizedName)
        state.switchOverZoomFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
        state.lensPosition = device.lensPosition
        state.iso = device.iso
        state.exposureDuration = device.exposureDuration.seconds
        state.exposureBias = device.exposureTargetBias
        state.exposureBiasRange = device.minExposureTargetBias...device.maxExposureTargetBias
        state.zoom = Double(device.videoZoomFactor)
        let maxZoom = min(Double(device.maxAvailableVideoZoomFactor), 15)
        state.zoomRange = Double(device.minAvailableVideoZoomFactor)...max(maxZoom, Double(device.minAvailableVideoZoomFactor))
        state.zoomDisplayMultiplier = Double(device.displayVideoZoomFactorMultiplier)
        state.hdrSupported = device.activeFormat.isVideoHDRSupported
        state.hdrEnabled = device.isVideoHDREnabled
        state.hdrAutomatic = device.automaticallyAdjustsVideoHDREnabled
        state.lensAperture = device.lensAperture
        state.fieldOfView = device.activeFormat.videoFieldOfView
        state.depthFormats = device.activeFormat.supportedDepthDataFormats.map(Self.formatSummary)
        state.activeDepthFormat = device.activeDepthDataFormat.map(Self.formatSummary)
        #endif
        let inputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        state.hasAudioInput = inputs.contains { $0.device.hasMediaType(.audio) }
        state.hasMovieOutput = session.outputs.contains(movieOutput)
        if session.outputs.contains(photoOutput) {
            state.hasPhotoOutput = true
            state.photoCodecs = CameraPhotoCodec.allCases.filter { photoOutput.availablePhotoCodecTypes.contains($0.codecType) }
            state.flashModes = CameraFlashSetting.allCases.filter { photoOutput.supportedFlashModes.contains($0.flashMode) }
            let dimensions = photoOutput.maxPhotoDimensions
            state.maxPhotoDimensions = CameraLabFormat.dimensions(width: Int(dimensions.width), height: Int(dimensions.height))
            #if os(iOS)
            state.depthDeliverySupported = photoOutput.isDepthDataDeliverySupported
            state.depthDeliveryEnabled = photoOutput.isDepthDataDeliveryEnabled
            #endif
        }
        return state
    }

    /// Runs on sessionQueue: returns an error message or nil when the capture request was accepted.
    nonisolated private func requestPhoto(_ request: CameraPhotoRequest) -> String? {
        guard session.isRunning, session.outputs.contains(photoOutput) else { return "The photo output is not running." }
        let codecType = request.codec.codecType
        guard photoOutput.availablePhotoCodecTypes.contains(codecType) else {
            return "\(request.codec.rawValue) is not in availablePhotoCodecTypes for this camera configuration."
        }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codecType])
        if photoOutput.supportedFlashModes.contains(request.flash.flashMode) { settings.flashMode = request.flash.flashMode }
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        #if os(iOS)
        settings.isDepthDataDeliveryEnabled = request.depth && photoOutput.isDepthDataDeliveryEnabled
        #endif
        if let angle = request.rotation, let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
        return nil
    }

    private func updateDevice(report: String? = nil, _ change: @escaping @Sendable (AVCaptureDevice) throws -> Void) {
        guard isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = videoDevice else { return }
            var failure: String?
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                try change(device)
            } catch {
                failure = error.localizedDescription
            }
            let state = readState(device)
            Task { @MainActor in
                guard self.isRunning else { return }
                self.state = state
                if let failure { self.output = "Camera setting failed: \(failure)" } else if let report { self.output = report }
            }
        }
    }

    /// Refreshes live readouts (ISO, exposure, lens position, adjusting flags) once per second.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRunning else { return }
                self.refreshState()
            }
        }
    }

    private func refreshState() {
        sessionQueue.async { [weak self] in
            guard let self, let device = videoDevice else { return }
            let state = readState(device)
            Task { @MainActor in if self.isRunning { self.state = state } }
        }
    }

    /// Keeps the preview upright and records the capture angle for photos and movies.
    private func followRotation() {
        guard let device = AVCaptureDevice(uniqueID: selectedDeviceID) else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { @Sendable [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.applyPreviewRotation(angle) }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func observeSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { @Sendable [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "unknown error"
            Task { @MainActor in self?.output = "AVCaptureSession runtime error: \(message)" }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { @Sendable [weak self] note in
            let reason = Self.interruptionReason(note.userInfo)
            Task { @MainActor in self?.output = "The capture session was interrupted: \(reason)." }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor in self?.output = "The capture session interruption ended; the camera is running again." }
        })
    }

    nonisolated private static func interruptionReason(_ userInfo: [AnyHashable: Any]?) -> String {
        #if os(iOS)
        guard let raw = userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: raw) else { return "no reason given" }
        switch reason {
        case .videoDeviceNotAvailableInBackground: return "the camera is not available while the app is in the background"
        case .audioDeviceInUseByAnotherClient: return "another app is using the microphone"
        case .videoDeviceInUseByAnotherClient: return "another app is using the camera"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "the camera is not available with multiple foreground apps (Split View / Slide Over)"
        case .videoDeviceNotAvailableDueToSystemPressure: return "the camera was shut down due to system pressure (thermal state)"
        default: return "interruption reason \(raw)"
        }
        #else
        return "the camera became unavailable"
        #endif
    }

    #if os(iOS)
    nonisolated private static let deviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera,
        .builtInTripleCamera, .builtInTrueDepthCamera, .builtInLiDARDepthCamera, .external,
    ]
    #else
    nonisolated private static let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external]
    #endif

    nonisolated static func typeName(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInWideAngleCamera: return "Wide angle"
        case .external: return "External"
        default: break
        }
        #if os(iOS)
        switch type {
        case .builtInUltraWideCamera: return "Ultra wide"
        case .builtInTelephotoCamera: return "Telephoto"
        case .builtInDualCamera: return "Dual (virtual: wide + telephoto)"
        case .builtInDualWideCamera: return "Dual Wide (virtual: ultra wide + wide)"
        case .builtInTripleCamera: return "Triple (virtual: ultra wide + wide + telephoto)"
        case .builtInTrueDepthCamera: return "TrueDepth"
        case .builtInLiDARDepthCamera: return "LiDAR depth (virtual: LiDAR + wide)"
        default: break
        }
        #else
        switch type {
        case .continuityCamera: return "Continuity Camera"
        case .deskViewCamera: return "Desk View"
        default: break
        }
        #endif
        return type.rawValue
    }

    nonisolated static func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back: "Back"
        case .front: "Front"
        default: "Unspecified"
        }
    }

    nonisolated static func formatSummary(_ format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let rates = format.videoSupportedFrameRateRanges
        let minRate = rates.map(\.minFrameRate).min() ?? 0
        let maxRate = rates.map(\.maxFrameRate).max() ?? 0
        let subtype = CameraLabFormat.fourCC(CMFormatDescriptionGetMediaSubType(format.formatDescription))
        let rateText = rates.isEmpty ? "" : " · \(Int(minRate))–\(Int(maxRate)) fps"
        return "\(dimensions.width) × \(dimensions.height)\(rateText) · \(subtype)"
    }
    #else
    private func reconfigure(start: Bool) {}
    #endif
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
nonisolated private struct CameraSessionOptions: Sendable {
    let mode: CameraCaptureMode
    let depth: Bool
    let audio: Bool
}

nonisolated private struct CameraPhotoRequest: Sendable {
    let codec: CameraPhotoCodec
    let flash: CameraFlashSetting
    let depth: Bool
    let rotation: CGFloat?
}

nonisolated extension CameraFocusBehavior {
    var focusMode: AVCaptureDevice.FocusMode {
        switch self {
        case .continuous: .continuousAutoFocus
        case .single: .autoFocus
        case .locked: .locked
        }
    }
}

nonisolated extension CameraPhotoCodec {
    var codecType: AVVideoCodecType { self == .hevc ? .hevc : .jpeg }
}

nonisolated extension CameraFlashSetting {
    var flashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .auto: .auto
        case .on: .on
        }
    }
}

/// Receives AVFoundation's photo and recording callbacks on its internal queues and hands Sendable results to the service.
/// The photo output only keeps a weak reference to its delegate, so the service owns this object.
nonisolated final class CameraCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    /// Set once on the main actor before any capture starts.
    weak var service: CameraLabService?

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let result = Self.process(photo, error: error)
        let service = service
        Task { @MainActor in service?.didFinishPhoto(result) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        // Reaching maxRecordedDuration reports an error although the file was finished successfully.
        let finished = ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? (error == nil)
        let message = finished ? nil : error?.localizedDescription
        let note = finished && error != nil ? error?.localizedDescription : nil
        let hasAudio = connections.contains { connection in connection.inputPorts.contains { $0.mediaType == .audio } }
        let service = service
        Task { @MainActor in service?.didFinishRecording(url: outputFileURL, error: message ?? note, hasAudio: hasAudio) }
    }

    private static func process(_ photo: AVCapturePhoto, error: (any Error)?) -> Result<CameraCapturedPhoto, CameraLabError> {
        if let error { return .failure(CameraLabError(message: "Photo capture failed: \(error.localizedDescription)")) }
        guard let data = photo.fileDataRepresentation() else { return .failure(CameraLabError(message: "The captured photo has no file data representation.")) }
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let type = source.flatMap { CGImageSourceGetType($0) as String? }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CameraLab-\(Int(Date().timeIntervalSince1970)).\(type == "public.heic" ? "heic" : "jpg")")
        do { try data.write(to: url) } catch { return .failure(CameraLabError(message: "Could not store the photo: \(error.localizedDescription)")) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600]
        let image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        let size = photo.resolvedSettings.photoDimensions
        var depth: [CameraMetadataRow] = []
        #if os(iOS)
        let metadata = photo.metadata
        if let depthData = photo.depthData { depth = depthRows(depthData) }
        #else
        // AVCapturePhoto.metadata is iOS-only; on the Mac the same EXIF/TIFF dictionaries are read back from the file data.
        let metadata = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        #endif
        return .success(CameraCapturedPhoto(image: image, fileURL: url, byteCount: data.count,
                                            dimensions: CameraLabFormat.dimensions(width: Int(size.width), height: Int(size.height)),
                                            metadata: CameraLabFormat.metadataRows(metadata), depth: depth))
    }

    #if os(iOS)
    private static func depthRows(_ depth: AVDepthData) -> [CameraMetadataRow] {
        let map = depth.depthDataMap
        var rows = [
            CameraMetadataRow(title: "Depth map", value: "\(CVPixelBufferGetWidth(map)) × \(CVPixelBufferGetHeight(map))"),
            CameraMetadataRow(title: "Depth type", value: CameraLabFormat.depthTypeName(depth.depthDataType)),
            CameraMetadataRow(title: "Accuracy", value: depth.depthDataAccuracy == .absolute ? "Absolute (metric)" : "Relative"),
            CameraMetadataRow(title: "Quality", value: depth.depthDataQuality == .high ? "High" : "Low"),
            CameraMetadataRow(title: "Filtered", value: depth.isDepthDataFiltered ? "Yes (holes filled)" : "No"),
        ]
        if let calibration = depth.cameraCalibrationData {
            let reference = calibration.intrinsicMatrixReferenceDimensions
            rows.append(CameraMetadataRow(title: "Calibration", value: String(format: "%.0f × %.0f reference, pixel size %.4f mm", reference.width, reference.height, calibration.pixelSize)))
        }
        return rows
    }
    #endif
}
#endif
