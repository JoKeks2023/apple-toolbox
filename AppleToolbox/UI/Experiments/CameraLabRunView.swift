import SwiftUI
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CameraLabRunView: View {
    @StateObject private var camera = CameraLabService()

    var body: some View {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        Picker("Camera", selection: Binding(get: { camera.selectedDeviceID }, set: camera.selectDevice)) {
            if camera.devices.isEmpty { Text("No camera found").tag("") }
            ForEach(camera.devices) { device in
                Text(device.name).tag(device.id)
            }
        }
        .disabled(camera.devices.isEmpty || camera.isRecording || camera.isConfiguring)
        Picker("Mode", selection: Binding(get: { camera.mode }, set: camera.setMode)) {
            ForEach(CameraCaptureMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .disabled(camera.isRecording || camera.isConfiguring)
        if camera.mode == .video {
            Toggle("Record microphone audio", isOn: Binding(get: { camera.recordsAudio }, set: camera.setRecordsAudio))
                .disabled(camera.isRecording || camera.isConfiguring)
        }
        HStack {
            Button(camera.isRunning ? "Stop Camera" : camera.isConfiguring ? "Starting…" : "Start Camera",
                   systemImage: camera.isRunning ? "stop.fill" : "camera") {
                camera.isRunning ? camera.stop() : camera.start()
            }
            .buttonStyle(.borderedProminent)
            .disabled(camera.isConfiguring || camera.devices.isEmpty)
            if camera.isRunning {
                switch camera.mode {
                case .photo:
                    Button(camera.isCapturingPhoto ? "Capturing…" : "Take Photo", systemImage: "camera.shutter.button", action: camera.capturePhoto)
                        .buttonStyle(.bordered)
                        .disabled(camera.isCapturingPhoto)
                case .video:
                    Button(camera.isRecording ? "Stop Recording" : "Record", systemImage: camera.isRecording ? "stop.circle.fill" : "record.circle", action: camera.toggleRecording)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            }
        }
        .experimentSession(camera)
        if let started = camera.recordingStartedAt {
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                LabeledContent("Recording", value: "\(CameraLabFormat.duration(context.date.timeIntervalSince(started))) of max. \(CameraLabFormat.duration(CameraLabService.maxRecordingSeconds))")
                    .monospacedDigit()
            }
        }
        if camera.isRunning || camera.isConfiguring {
            CameraPreviewSection(camera: camera)
        }
        OutputView(text: camera.output, isError: camera.isError)
        if camera.isRunning, let state = camera.state {
            CameraControlsSection(camera: camera, state: state)
            CameraDeviceSection(state: state)
        }
        if let photo = camera.lastPhoto {
            CameraPhotoSection(photo: photo)
        }
        if let movie = camera.lastMovie {
            CameraMovieSection(movie: movie)
        }
        #else
        OutputView(text: camera.output, isError: true)
        #endif
    }
}

#if canImport(AVFoundation) && (os(iOS) || os(macOS))
private struct CameraPreviewSection: View {
    @ObservedObject var camera: CameraLabService

    var body: some View {
        ZStack {
            CameraPreviewView(camera: camera)
            if let marker = camera.focusMarker {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.yellow, lineWidth: 2)
                    .frame(width: 64, height: 64)
                    .position(marker)
                    .allowsHitTesting(false)
            }
            if camera.isConfiguring {
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        Text("AVCaptureVideoPreviewLayer shows the full frame (aspect fit). Tap to set the focus and exposure point of interest.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct CameraControlsSection: View {
    @ObservedObject var camera: CameraLabService
    let state: CameraDeviceState

    var body: some View {
        Section("Controls") {
            if state.focusModes.isEmpty {
                LabeledContent("Focus", value: "Fixed focus (no focus modes)")
            } else {
                Picker("Focus", selection: Binding(get: { camera.focusBehavior }, set: camera.setFocusBehavior)) {
                    ForEach(state.focusModes) { Text($0.rawValue).tag($0) }
                }
            }
            LabeledContent("Tap to focus", value: state.supportsFocusPoint ? "Focus and exposure point" : state.supportsExposurePoint ? "Exposure point only" : "Not supported")
            if let range = state.exposureBiasRange, range.upperBound > range.lowerBound {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Exposure bias", value: String(format: "%+.1f EV", state.exposureBias))
                    Slider(value: Binding(get: { state.exposureBias }, set: camera.setExposureBias), in: range, step: 0.1)
                }
            } else {
                LabeledContent("Exposure bias", value: Self.unavailable)
            }
            if let range = state.zoomRange, range.upperBound > range.lowerBound {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Zoom", value: "\(CameraLabFormat.zoom(state.zoom, multiplier: state.zoomDisplayMultiplier)) (videoZoomFactor \(String(format: "%.2f", state.zoom)))")
                    Slider(value: Binding(get: { state.zoom }, set: camera.setZoom), in: range)
                    if !state.switchOverZoomFactors.isEmpty {
                        Text("Lens switch-over at \(state.switchOverZoomFactors.map { CameraLabFormat.zoom($0, multiplier: state.zoomDisplayMultiplier) }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                LabeledContent("Zoom", value: state.zoomRange == nil ? Self.unavailable : "This camera has a fixed 1× zoom range")
            }
            if state.hasTorch {
                Toggle("Torch", isOn: Binding(get: { state.torchOn }, set: camera.setTorch))
                    .disabled(!state.torchAvailable)
            } else {
                LabeledContent("Torch", value: "No torch on this camera")
            }
            if state.hdrSupported {
                Picker("Video HDR", selection: Binding(get: { state.hdrAutomatic ? .automatic : state.hdrEnabled ? .on : .off }, set: camera.setHDR)) {
                    ForEach(CameraHDRSetting.allCases) { Text($0.rawValue).tag($0) }
                }
                LabeledContent("HDR streaming", value: state.hdrEnabled ? "On" : "Off")
            } else {
                LabeledContent("Video HDR", value: Self.isMac ? Self.unavailable : "Not supported by the active format")
            }
            if camera.mode == .photo {
                if state.photoCodecs.isEmpty {
                    LabeledContent("Photo format", value: "No compressed codec available")
                } else {
                    Picker("Photo format", selection: $camera.codec) {
                        ForEach(state.photoCodecs) { Text($0.rawValue).tag($0) }
                    }
                }
                if state.flashModes.count > 1 {
                    Picker("Flash", selection: $camera.flash) {
                        ForEach(state.flashModes) { Text($0.rawValue).tag($0) }
                    }
                } else {
                    LabeledContent("Flash", value: state.hasFlash ? "Not offered by the photo output" : "No flash on this camera")
                }
                if state.depthDeliverySupported {
                    Toggle("Deliver depth data with photos", isOn: Binding(get: { camera.deliversDepth }, set: camera.setDeliversDepth))
                } else {
                    LabeledContent("Depth data", value: Self.isMac ? Self.unavailable : "Not supported by this camera and format")
                }
            }
        }
    }

    private static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private static let unavailable = isMac ? "Not available on macOS (iOS/iPadOS API)" : "Not supported by this camera"
}

private struct CameraDeviceSection: View {
    let state: CameraDeviceState

    var body: some View {
        Section("Camera") {
            LabeledContent("Device", value: state.deviceName)
            LabeledContent("Type", value: state.typeName)
            LabeledContent("Position", value: state.position)
            LabeledContent("Active format") { Text(state.activeFormat).font(.caption.monospaced()) }
            if state.isVirtual { LabeledContent("Constituent cameras", value: state.constituents.joined(separator: ", ")) }
            if let dimensions = state.maxPhotoDimensions { LabeledContent("Max photo size", value: dimensions) }
            if let aperture = state.lensAperture { LabeledContent("Aperture", value: CameraLabFormat.aperture(Double(aperture))) }
            if let fieldOfView = state.fieldOfView, fieldOfView > 0 { LabeledContent("Field of view", value: String(format: "%.1f°", fieldOfView)) }
            if let distance = state.minimumFocusDistance { LabeledContent("Minimum focus distance", value: "\(distance) mm") }
            if let iso = state.iso { LabeledContent("ISO (live)", value: String(format: "%.0f", iso)) }
            if let exposure = state.exposureDuration { LabeledContent("Exposure (live)", value: CameraLabFormat.exposure(exposure)) }
            if let lens = state.lensPosition { LabeledContent("Lens position (live)", value: String(format: "%.2f", lens)) }
            LabeledContent("Adjusting", value: [state.isAdjustingFocus ? "focus" : nil, state.isAdjustingExposure ? "exposure" : nil].compactMap { $0 }.joined(separator: ", ").nonEmpty ?? "Nothing")
            #if os(iOS)
            LabeledContent("Depth formats", value: state.depthFormats.isEmpty ? "None" : "\(state.depthFormats.count) · active: \(state.activeDepthFormat ?? "none")")
            #endif
        }
    }
}

private struct CameraPhotoSection: View {
    let photo: CameraCapturedPhoto

    var body: some View {
        Section("Last photo") {
            if let image = photo.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            LabeledContent("File", value: "\(photo.fileURL.pathExtension.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(photo.byteCount), countStyle: .file))")
            LabeledContent("Dimensions", value: photo.dimensions)
            ForEach(photo.metadata) { LabeledContent($0.title, value: $0.value) }
            if !photo.depth.isEmpty {
                Text("AVDepthData").font(.subheadline.weight(.semibold))
                ForEach(photo.depth) { LabeledContent($0.title, value: $0.value) }
            }
            ShareLink(item: photo.fileURL) {
                Label("Share Photo", systemImage: "square.and.arrow.up")
            }
        }
    }
}

private struct CameraMovieSection: View {
    let movie: CameraRecordedMovie

    var body: some View {
        Section("Last recording") {
            LabeledContent("Duration", value: CameraLabFormat.duration(movie.duration))
            LabeledContent("File", value: "MOV · \(ByteCountFormatter.string(fromByteCount: movie.byteCount, countStyle: .file))")
            LabeledContent("Audio", value: movie.hasAudio ? "Microphone track included" : "Video only")
            ShareLink(item: movie.fileURL) {
                Label("Share Video", systemImage: "square.and.arrow.up")
            }
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if os(iOS)
private struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraLabService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = camera.previewSession
        view.onTap = { [weak camera] viewPoint, devicePoint in camera?.focus(atDevicePoint: devicePoint, viewPoint: viewPoint) }
        camera.attachPreview(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onTap: ((CGPoint, CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspect
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) { nil }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        onTap?(point, previewLayer.captureDevicePointConverted(fromLayerPoint: point))
    }
}
#elseif os(macOS)
private struct CameraPreviewView: NSViewRepresentable {
    let camera: CameraLabService

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = camera.previewSession
        view.onTap = { [weak camera] viewPoint, devicePoint in camera?.focus(atDevicePoint: devicePoint, viewPoint: viewPoint) }
        camera.attachPreview(view.previewLayer)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}
}

final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var onTap: ((CGPoint, CGPoint) -> Void)?

    init() {
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer = previewLayer // Layer-hosting view: the preview layer is the view's backing layer.
        wantsLayer = true
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
    }

    required init?(coder: NSCoder) { nil }

    @objc private func clicked(_ recognizer: NSClickGestureRecognizer) {
        // AppKit and the hosted layer use a bottom-left origin; SwiftUI overlays use a top-left one.
        let point = recognizer.location(in: self)
        onTap?(CGPoint(x: point.x, y: bounds.height - point.y), previewLayer.captureDevicePointConverted(fromLayerPoint: point))
    }
}
#endif
#endif
