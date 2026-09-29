import SwiftUI
#if canImport(ARKit) && canImport(RealityKit) && os(iOS)
import RealityKit
import UIKit
#endif

struct ARLabRunView: View {
    @StateObject private var ar = ARLabService()

    var body: some View {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        Picker("Configuration", selection: Binding(get: { ar.mode }, set: ar.setMode)) {
            ForEach(ARLabMode.allCases) { mode in
                Text(ar.isSupported(mode) ? mode.rawValue : "\(mode.rawValue) — unsupported").tag(mode)
            }
        }
        if ar.mode == .world || ar.mode == .body {
            Picker("Plane detection", selection: Binding(get: { ar.planeDetection }, set: ar.setPlaneDetection)) {
                ForEach(ARLabPlaneDetection.allCases) { Text($0.rawValue).tag($0) }
            }
        }
        if ar.mode == .world {
            Toggle("Scene reconstruction mesh", isOn: Binding(get: { ar.sceneReconstruction }, set: ar.setSceneReconstruction))
                .disabled(!ar.supportsMesh)
            Toggle("Occlusion (people, and mesh with LiDAR)", isOn: Binding(get: { ar.occlusion }, set: ar.setOcclusion))
                .disabled(!ar.supportsOcclusion)
            if !ar.supportsMesh {
                Text("Scene reconstruction needs a LiDAR Scanner: supportsSceneReconstruction(.mesh) is false on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Toggle("Show feature points and anchor origins", isOn: Binding(get: { ar.showsDebug }, set: ar.setShowsDebug))
        HStack {
            Button(ar.isRunning ? "Stop AR Session" : "Start AR Session", systemImage: ar.isRunning ? "stop.fill" : "arkit") {
                ar.isRunning ? ar.stop() : ar.start()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ar.isRunning && !ar.isSupported(ar.mode))
            if ar.isRunning && ar.placedCount > 0 {
                Button("Remove \(ar.placedCount)", systemImage: "trash", action: ar.removePlacedEntities)
                    .buttonStyle(.bordered)
            }
        }
        .experimentSession(ar)
        if ar.isRunning, let view = ar.arView {
            ARViewContainer(view: view)
                .frame(maxWidth: .infinity)
                .frame(height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Label(ar.stats.trackingState, systemImage: ar.stats.trackingState == "Normal" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
        }
        OutputView(text: ar.output, isError: ar.isError)
        Section("RealityKit entity") {
            Picker("Shape", selection: $ar.shape) {
                ForEach(ARLabShape.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Material", selection: $ar.material) {
                ForEach(ARLabMaterial.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Color", selection: $ar.color) {
                ForEach(ARLabColor.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("Physics (drop onto horizontal surfaces)", isOn: $ar.physics)
            Picker("Animation", selection: $ar.animation) {
                ForEach(ARLabAnimation.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Tap a surface to place the entity via ARView.raycast. With physics on horizontal surfaces it falls onto an invisible static floor (and onto the LiDAR mesh when reconstruction is on); otherwise it plays the animation. Tap a placed entity to push or pulse it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if ar.mode == .image {
            ARReferenceImageSection(ar: ar)
        }
        Section("Tracking") {
            LabeledContent("Tracking state", value: ar.stats.trackingState)
            LabeledContent("World mapping", value: ar.stats.worldMapping)
            LabeledContent("Frame rate", value: ar.stats.frames == 0 ? "—" : String(format: "%.0f fps", ar.stats.framesPerSecond)).monospacedDigit()
            LabeledContent("Frames", value: "\(ar.stats.frames)").monospacedDigit()
            LabeledContent("Camera image", value: ar.stats.cameraResolution)
            LabeledContent("Feature points", value: "\(ar.stats.featurePoints)").monospacedDigit()
            if let light = ar.stats.lightEstimate { LabeledContent("Light estimate", value: light) }
            if let depth = ar.stats.sceneDepth { LabeledContent("Scene depth", value: depth) }
            LabeledContent("Anchors in frame", value: "\(ar.stats.anchorCount)").monospacedDigit()
        }
        Section("Anchors (\(ar.anchors.count))") {
            if ar.anchors.isEmpty {
                Text("ARAnchors (planes, meshes, faces, bodies, images, placed entities) appear here while the session runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ar.anchors.prefix(40)) { anchor in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anchor.title).font(.subheadline.weight(.semibold))
                        Text(anchor.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if ar.anchors.count > 40 {
                    Text("and \(ar.anchors.count - 40) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section("Configuration support on this device") {
            ForEach(ar.support) { row in
                LabeledContent {
                    Text(row.detail).font(.caption).multilineTextAlignment(.trailing)
                } label: {
                    Label(row.title, systemImage: row.supported == true ? "checkmark.circle.fill" : row.supported == false ? "xmark.octagon.fill" : "minus.circle")
                }
            }
        }
        #else
        OutputView(text: ar.output, isError: true)
        #endif
    }
}

#if canImport(ARKit) && canImport(RealityKit) && os(iOS)
private struct ARReferenceImageSection: View {
    @ObservedObject var ar: ARLabService

    var body: some View {
        Section("Reference image") {
            if let image = ar.referenceImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
            }
            LabeledContent("Physical width", value: String(format: "%.0f cm", ARLabService.referenceImageWidth * 100))
            LabeledContent("ARKit validation", value: ar.referenceValidation ?? "Not generated yet")
            if let url = ar.referenceImageURL {
                ShareLink(item: url) {
                    Label("Share Reference Image", systemImage: "square.and.arrow.up")
                }
            }
            Text("The app bundles no AR reference assets, and its icon has too little detail for ARKit, so this pattern is rendered at runtime. Show it on another screen or print it about 15 cm wide, then point the camera at it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Hosts the service-owned ARView, so placed entities survive when the list row is recreated.
private struct ARViewContainer: UIViewRepresentable {
    let view: ARView

    func makeUIView(context: Context) -> ARView { view }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif
