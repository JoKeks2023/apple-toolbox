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
        if ar.mode == .world {
            ARWorldMapSection(ar: ar)
        }
        if ar.mode == .objectScan {
            ARObjectScanSection(ar: ar)
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
/// Save and restore an ARWorldMap (with the placed entities' ARAnchors) to a file.
private struct ARWorldMapSection: View {
    @ObservedObject var ar: ARLabService

    var body: some View {
        Section("World map · ARWorldMap") {
            LabeledContent("Mapping status", value: ar.isRunning ? ar.mappingReadiness.rawValue : "Session not running")
            Text(ar.mappingReadiness.advice)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(ar.isSavingWorldMap ? "Saving…" : "Save World Map", systemImage: "square.and.arrow.down") { ar.saveWorldMap() }
                    .buttonStyle(.bordered)
                    .disabled(!ar.isRunning || !ar.mappingReadiness.canSave || ar.isSavingWorldMap)
                Button("Restore", systemImage: "arrow.counterclockwise") { ar.restoreWorldMap() }
                    .buttonStyle(.bordered)
                    .disabled(ar.worldMapFileURL == nil)
            }
            if let url = ar.worldMapFileURL {
                LabeledContent("Saved file", value: url.lastPathComponent)
                if let info = ar.worldMapInfo { LabeledContent("Contents", value: info) }
                HStack {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button("Delete", systemImage: "trash", role: .destructive) { ar.deleteWorldMap() }
                }
            }
            Text("Placed entities are backed by named ARAnchors, so they are part of the saved map. After Restore, ARKit relocalizes against the saved feature points and the entities reappear where they were.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// ARObjectScanningConfiguration → ARReferenceObject → detection in world tracking.
private struct ARObjectScanSection: View {
    @ObservedObject var ar: ARLabService

    var body: some View {
        Section("Object scanning · ARReferenceObject") {
            if !ar.isSupported(.objectScan) {
                Text("ARObjectScanningConfiguration.isSupported is false on this device, so ARKit cannot scan reference objects here. It needs an iPhone or iPad with an A9 chip or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Scan box", selection: $ar.scanExtent) {
                    ForEach(ARLabScanExtent.allCases) { Text($0.label).tag($0) }
                }
                .disabled(ar.hasScanBox)
                Button(ar.isCreatingReferenceObject ? "Creating…" : "Create Reference Object", systemImage: "cube.transparent") { ar.createReferenceObject() }
                    .buttonStyle(.bordered)
                    .disabled(!ar.isRunning || !ar.hasScanBox || ar.isCreatingReferenceObject)
                if let info = ar.scannedObjectInfo { LabeledContent("Reference object", value: info) }
                if let url = ar.scannedObjectFileURL {
                    ShareLink(item: url) { Label("Share .arobject", systemImage: "square.and.arrow.up") }
                }
                if ar.hasScannedObject {
                    Button("Detect in World Tracking", systemImage: "viewfinder") { ar.detectScannedObject() }
                        .buttonStyle(.bordered)
                }
                Text("Tap the surface under the object to place the scan box, walk around it, then create the reference object. Scanning takes several seconds of feature collection; plain or shiny objects often fail with a real ARError.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

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
