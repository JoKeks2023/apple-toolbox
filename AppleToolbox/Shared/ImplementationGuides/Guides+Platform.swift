import Foundation

nonisolated extension ImplementationGuides {
    static let platform: [String: ImplementationGuide] = [
        "metal": ImplementationGuide(
            snippet: #"""
            import Metal

            /// Compiles a compute kernel at runtime and doubles every value on the GPU.
            func doubleOnGPU(_ input: [Float]) throws -> [Float] {
                guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                      let buffer = device.makeBuffer(bytes: input, length: input.count * MemoryLayout<Float>.stride,
                                                     options: .storageModeShared) else { return input }
                let source = """
                #include <metal_stdlib>
                using namespace metal;
                kernel void double_values(device float *values [[buffer(0)]], uint id [[thread_position_in_grid]]) {
                    values[id] *= 2.0;
                }
                """
                let library = try device.makeLibrary(source: source, options: nil)
                let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "double_values")!)

                guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else { return input }
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.dispatchThreads(MTLSize(width: input.count, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: min(input.count, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
                encoder.endEncoding()
                commands.commit()
                commands.waitUntilCompleted() // Blocks: call this off the main thread.

                let result = buffer.contents().bindMemory(to: Float.self, capacity: input.count)
                return Array(UnsafeBufferPointer(start: result, count: input.count))
            }
            """#,
            notes: [
                "Put shaders in .metal files for production: Xcode precompiles them into default.metallib (device.makeDefaultLibrary()).",
                "Create the device, queue and pipeline states once and reuse them; they are expensive.",
                "The Simulator's GPU lacks some features; test Metal code on a device.",
            ]
        ),
        "mac-hardware": ImplementationGuide(
            platform: .macOS,
            snippet: #"""
            import AppKit
            import AVFoundation
            import CoreAudio

            /// Lists cameras, microphones, displays and volumes without asking for any permission.
            @MainActor
            func hardwareInventory() -> [String] {
                let cameras = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)
                let microphones = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
                let displays = NSScreen.screens.map {
                    "Display: \($0.localizedName) \(Int($0.frame.width))×\(Int($0.frame.height)) @\($0.backingScaleFactor)x"
                }
                let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                                    options: .skipHiddenVolumes) ?? []
                return cameras.devices.map { "Camera: \($0.localizedName)" }
                    + microphones.devices.map { "Microphone: \($0.localizedName)" }
                    + displays
                    + volumes.map { "Volume: \($0.lastPathComponent)" }
                    + ["Core Audio devices: \(audioDeviceCount())"]
            }

            func audioDeviceCount() -> Int {
                var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                         mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                var size: UInt32 = 0
                AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
                return Int(size) / MemoryLayout<AudioDeviceID>.size
            }
            """#,
            notes: [
                "Listing devices needs no permission; capturing needs NSCameraUsageDescription / NSMicrophoneUsageDescription and, sandboxed, the camera or audio-input entitlement.",
                "Observe AVCaptureDevice.wasConnectedNotification and NSApplication.didChangeScreenParametersNotification for hot-plugging.",
            ]
        ),
        "apple-pencil": ImplementationGuide(
            snippet: #"""
            import PencilKit
            import UIKit

            /// A PencilKit canvas that reacts to double-tap, squeeze and hover.
            final class SketchViewController: UIViewController, UIPencilInteractionDelegate, PKCanvasViewDelegate {
                private let canvas = PKCanvasView()

                override func viewDidLoad() {
                    super.viewDidLoad()
                    canvas.frame = view.bounds
                    canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    canvas.drawingPolicy = .pencilOnly // Fingers scroll, Pencil draws.
                    canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
                    canvas.delegate = self
                    view.addSubview(canvas)
                    view.addInteraction(UIPencilInteraction(delegate: self))
                    view.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered)))
                }

                func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
                    guard let point = canvasView.drawing.strokes.last?.path.last else { return }
                    print("Force \(point.force), altitude \(point.altitude), azimuth \(point.azimuth)")
                }

                @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
                    print("Hovering \(recognizer.zOffset) above the screen") // 0...1, M2 iPad or later.
                }

                func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
                    canvas.tool = PKEraserTool(.vector)
                }

                func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
                    if squeeze.phase == .ended { print("Squeezed at \(squeeze.hoverPose?.location ?? .zero)") }
                }
            }
            """#,
            notes: [
                "Respect UIPencilInteraction.preferredTapAction / preferredSqueezeAction: the user picks what double-tap and squeeze do.",
                "Squeeze and barrel roll need Apple Pencil Pro and iPadOS 17.5+; hover needs an M2 iPad or later.",
                "For raw pressure and tilt outside PencilKit, read UITouch.force, altitudeAngle and azimuthAngle(in:) of .pencil touches.",
            ]
        ),
        "pointer-keyboard": ImplementationGuide(
            snippet: #"""
            import GameController
            import SwiftUI

            /// Shows the last key press and the pointer position over the view.
            struct InputInspector: View {
                @State private var lastKey = "–"
                @State private var pointer: CGPoint?
                @FocusState private var focused: Bool

                var body: some View {
                    VStack {
                        Text("Key: \(lastKey)")
                        Text(pointer.map { "Pointer: \(Int($0.x)), \(Int($0.y))" } ?? "Pointer outside")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focused)
                    .onAppear { focused = true } // onKeyPress only fires on the focused view.
                    .onKeyPress(phases: .down) { press in
                        lastKey = (press.modifiers.contains(.command) ? "⌘" : "") + press.characters
                        return .handled
                    }
                    .onContinuousHover { phase in
                        if case .active(let location) = phase { pointer = location } else { pointer = nil }
                    }
                }
            }

            /// Raw hardware key codes, independent of focus and text input.
            func logRawKeys() {
                GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { _, _, keyCode, pressed in
                    print("Key \(keyCode.rawValue) \(pressed ? "down" : "up")")
                }
            }
            """#,
            notes: [
                "GCKeyboard.coalesced is nil until a keyboard connects: observe .GCKeyboardDidConnect before setting the handler.",
                "Add .keyboardShortcut to buttons and menu commands so they appear in the iPad shortcut overlay (hold ⌘).",
                "Use .hoverEffect for pointer feedback on iPad; custom pointer shapes are macOS-only (.pointerStyle, macOS 15+).",
            ]
        ),
        "windows-displays": ImplementationGuide(
            snippet: #"""
            import SwiftUI
            import UIKit

            /// Shows the window's size and size class, and opens another window where supported.
            struct WindowInfoView: View {
                @Environment(\.horizontalSizeClass) private var horizontalSizeClass
                @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
                @Environment(\.openWindow) private var openWindow

                var body: some View {
                    GeometryReader { proxy in
                        VStack {
                            Text("Window: \(Int(proxy.size.width)) × \(Int(proxy.size.height)) pt")
                            Text("Horizontal size class: \(horizontalSizeClass == .compact ? "compact" : "regular")")
                            if supportsMultipleWindows {
                                Button("New window") { openWindow(id: "inspector") } // A WindowGroup(id: "inspector") scene.
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            /// Every connected scene with its role, e.g. an external display.
            @MainActor
            func sceneReport() -> [String] {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.map { scene in
                    let bounds = scene.effectiveGeometry.coordinateSpace.bounds
                    return "\(scene.session.role.rawValue): \(Int(bounds.width)) × \(Int(bounds.height)), \(scene.activationState)"
                }
            }
            """#,
            infoPlist: [
                .init(key: "UIApplicationSceneManifest",
                      value: "<dict><key>UIApplicationSupportsMultipleScenes</key><true/></dict>"),
            ],
            notes: [
                "Lay out by size class and available size, never by device model: iPad windows can be any size.",
                "Without UIApplicationSupportsMultipleScenes the app has one window and openWindow does nothing.",
                "An external display shows a mirrored copy unless the app handles the windowExternalDisplayNonInteractive scene role.",
            ]
        ),
    ]
}
