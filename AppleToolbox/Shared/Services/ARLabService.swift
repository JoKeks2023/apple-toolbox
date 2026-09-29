import Foundation
import Combine
import CoreGraphics
#if canImport(ARKit) && canImport(RealityKit) && os(iOS)
import ARKit
import RealityKit
import AVFoundation
import CoreVideo
import UIKit
import simd
#endif

// MARK: - Choices and snapshots

nonisolated enum ARLabMode: String, CaseIterable, Identifiable, Sendable {
    case world = "World tracking"
    case face = "Face tracking (TrueDepth)"
    case body = "Body tracking"
    case image = "Image tracking"
    var id: String { rawValue }

    var configurationName: String {
        switch self {
        case .world: "ARWorldTrackingConfiguration"
        case .face: "ARFaceTrackingConfiguration"
        case .body: "ARBodyTrackingConfiguration"
        case .image: "ARImageTrackingConfiguration"
        }
    }
}

nonisolated enum ARLabPlaneDetection: String, CaseIterable, Identifiable, Sendable {
    case none = "Off"
    case horizontal = "Horizontal"
    case vertical = "Vertical"
    case both = "Horizontal & vertical"
    var id: String { rawValue }
}

nonisolated enum ARLabShape: String, CaseIterable, Identifiable, Sendable {
    case box = "Box"
    case sphere = "Sphere"
    var id: String { rawValue }
}

nonisolated enum ARLabMaterial: String, CaseIterable, Identifiable, Sendable {
    case metallic = "Metallic (SimpleMaterial)"
    case matte = "Matte (SimpleMaterial)"
    case unlit = "Unlit (UnlitMaterial)"
    case clearcoat = "Clearcoat (PhysicallyBasedMaterial)"
    var id: String { rawValue }
}

nonisolated enum ARLabColor: String, CaseIterable, Identifiable, Sendable {
    case blue = "Blue"
    case red = "Red"
    case green = "Green"
    case orange = "Orange"
    case purple = "Purple"
    var id: String { rawValue }
}

nonisolated enum ARLabAnimation: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case spin = "Spin"
    case bounce = "Bounce"
    var id: String { rawValue }
}

nonisolated struct ARLabRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    var supported: Bool?
}

nonisolated struct ARLabFrameStats: Equatable, Sendable {
    var trackingState = "—"
    var worldMapping = "—"
    var framesPerSecond: Double = 0
    var frames = 0
    var cameraResolution = "—"
    var featurePoints = 0
    var lightEstimate: String?
    var sceneDepth: String?
    var anchorCount = 0
}

// MARK: - Formatting and the runtime reference pattern (pure, unit tested)

nonisolated enum ARLabFormat {
    static func meters(_ value: Float) -> String { String(format: "%.2f m", value) }

    static func fps(frames: Int, seconds: Double) -> Double {
        seconds > 0 ? Double(frames) / seconds : 0
    }

    /// One shape of the generated image-tracking pattern, in unit coordinates (0…1).
    struct PatternShape: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case rectangle, ellipse, triangle }
        let kind: Kind
        let rect: CGRect
        let hue: Double
        let rotation: Double
    }

    /// Deterministic, non-repeating high-contrast shapes (SplitMix64), so the reference image has the dense,
    /// unique features ARKit needs and looks the same on every run and device.
    static func patternShapes(seed: UInt64 = 0x41_54_42_2D_41_52, count: Int = 90) -> [PatternShape] {
        var state = seed
        func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        return (0..<count).map { _ in
            let size = 0.04 + next() * 0.16
            let height = size * (0.5 + next())
            let x = next() * (1 - size)
            let y = next() * (1 - height)
            let kinds: [PatternShape.Kind] = [.rectangle, .ellipse, .triangle]
            return PatternShape(kind: kinds[Int(next() * 3) % 3], rect: CGRect(x: x, y: y, width: size, height: height),
                                hue: next(), rotation: next() * .pi)
        }
    }
}

#if canImport(ARKit) && canImport(RealityKit) && os(iOS)
nonisolated extension ARLabFormat {
    static func trackingState(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: "Normal"
        case .notAvailable: "Not available"
        case .limited(.initializing): "Limited — initializing"
        case .limited(.excessiveMotion): "Limited — excessive motion"
        case .limited(.insufficientFeatures): "Limited — insufficient features"
        case .limited(.relocalizing): "Limited — relocalizing"
        case .limited: "Limited"
        }
    }

    static func worldMapping(_ status: ARFrame.WorldMappingStatus) -> String {
        switch status {
        case .notAvailable: "Not available"
        case .limited: "Limited"
        case .extending: "Extending"
        case .mapped: "Mapped"
        @unknown default: "Unknown"
        }
    }

    static func classification(_ classification: ARPlaneAnchor.Classification) -> String {
        switch classification {
        case .wall: "Wall"
        case .floor: "Floor"
        case .ceiling: "Ceiling"
        case .table: "Table"
        case .seat: "Seat"
        case .window: "Window"
        case .door: "Door"
        case .none(.notAvailable): "Unclassified (classification not available)"
        case .none(.undetermined): "Unclassified (undetermined yet)"
        case .none: "Unclassified"
        @unknown default: "Unknown classification"
        }
    }
}
#endif

// MARK: - Service

/// ARKit & RealityKit Lab: an ARView with world, face, body or image tracking, raycast placement of RealityKit
/// entities with physics, materials and animation, the live anchor list, frame statistics and a support matrix.
@MainActor
final class ARLabService: NSObject, ObservableObject {
    static let referenceImageWidth: Float = 0.15

    @Published private(set) var mode: ARLabMode = .world
    @Published private(set) var planeDetection: ARLabPlaneDetection = .both
    @Published private(set) var sceneReconstruction = false
    @Published private(set) var occlusion = false
    @Published private(set) var showsDebug = false
    @Published var shape: ARLabShape = .box
    @Published var material: ARLabMaterial = .metallic
    @Published var color: ARLabColor = .blue
    @Published var physics = true
    @Published var animation: ARLabAnimation = .spin
    @Published private(set) var isRunning = false
    @Published private(set) var stats = ARLabFrameStats()
    @Published private(set) var anchors: [ARLabRow] = []
    @Published private(set) var placedCount = 0
    @Published private(set) var output: String
    @Published private(set) var status: ExperimentStatus
    @Published private(set) var referenceImage: CGImage?
    @Published private(set) var referenceImageURL: URL?
    @Published private(set) var referenceValidation: String?
    let support: [ARLabRow]

    var isActive: Bool { isRunning }
    var isError: Bool { [.unavailable, .permissionDenied, .hardwareUnsupported, .platformUnsupported].contains(status) }

    #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
    @Published private(set) var arView: ARView?
    private var arReferenceImage: ARReferenceImage?
    private var trackedAnchors: [UUID: ARAnchor] = [:]
    private var imageEntities: [UUID: AnchorEntity] = [:]
    private var placedAnchors: [AnchorEntity] = []
    private var anchorsChanged = false
    private var windowStart: TimeInterval = 0
    private var windowFrames = 0
    private var totalFrames = 0
    #endif

    override init() {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        support = Self.supportRows()
        status = ExperimentAvailability.arKit()
        output = ARWorldTrackingConfiguration.isSupported
            ? "Choose a configuration and start the session. In world tracking, tap a detected surface to place an entity."
            : "ARWorldTrackingConfiguration.isSupported is false on this device, so world tracking cannot run."
        #else
        support = []
        status = .platformUnsupported
        output = "ARKit world tracking and RealityKit's ARView camera mode exist only on iPhone and iPad."
        #endif
        super.init()
    }

    // MARK: Options

    func isSupported(_ mode: ARLabMode) -> Bool {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        switch mode {
        case .world: ARWorldTrackingConfiguration.isSupported
        case .face: ARFaceTrackingConfiguration.isSupported
        case .body: ARBodyTrackingConfiguration.isSupported
        case .image: ARImageTrackingConfiguration.isSupported
        }
        #else
        false
        #endif
    }

    var supportsMesh: Bool {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        #else
        false
        #endif
    }

    var supportsOcclusion: Bool {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        supportsMesh || ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
        #else
        false
        #endif
    }

    func setMode(_ newMode: ARLabMode) {
        guard newMode != mode else { return }
        let wasRunning = isRunning
        if wasRunning { stop() }
        mode = newMode
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        if newMode == .image { prepareReferenceImage() }
        #endif
        if wasRunning { start() } else if !isSupported(newMode) {
            output = "\(newMode.configurationName).isSupported is false on this device. \(Self.unsupportedReason(newMode))"
        } else {
            output = "\(newMode.configurationName) is supported. Start the session to run it."
        }
    }

    func setPlaneDetection(_ value: ARLabPlaneDetection) {
        planeDetection = value
        rerunConfiguration()
    }

    func setSceneReconstruction(_ enabled: Bool) {
        sceneReconstruction = enabled && supportsMesh
        rerunConfiguration()
    }

    func setOcclusion(_ enabled: Bool) {
        occlusion = enabled && supportsOcclusion
        rerunConfiguration()
    }

    func setShowsDebug(_ enabled: Bool) {
        showsDebug = enabled
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        if let arView { applyEnvironment(to: arView) }
        #endif
    }

    // MARK: Session

    func start() {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        guard !isRunning else { return }
        guard isSupported(mode) else {
            status = .hardwareUnsupported
            output = "\(mode.configurationName).isSupported is false on this device. \(Self.unsupportedReason(mode))"
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            status = .permissionRequired
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
        if mode == .image { prepareReferenceImage() }
        let configuration = makeConfiguration()
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session.delegate = self // ARKit calls the delegate on the main queue (delegateQueue is nil).
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        applyEnvironment(to: view)
        arView = view
        resetState()
        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        addModeEntities(to: view)
        isRunning = true
        status = .available
        output = "\(mode.configurationName) running. \(Self.hint(for: mode))"
        #endif
    }

    func stop() {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        if let arView {
            arView.session.pause()
            arView.session.delegate = nil
            arView.scene.anchors.removeAll()
        }
        arView = nil
        resetState()
        #endif
        guard isRunning else { return }
        isRunning = false
        output = "AR session paused; the ARView and its entities were released."
    }

    func removePlacedEntities() {
        #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
        for anchor in placedAnchors { anchor.removeFromParent() }
        placedAnchors.removeAll()
        placedCount = 0
        output = "Removed all placed entities."
        #endif
    }

    private func reportDenied() {
        status = .permissionDenied
        output = "Camera access is denied or restricted, and ARKit needs the camera. Allow it in Settings › Privacy & Security › Camera."
    }

    nonisolated private static func unsupportedReason(_ mode: ARLabMode) -> String {
        switch mode {
        case .world: "World tracking needs an A9 or later chip and a rear camera."
        case .face: "Face tracking needs a TrueDepth camera (or an A12+ chip with a front camera)."
        case .body: "Body tracking needs an A12 Bionic or later."
        case .image: "Image tracking needs an A9 or later chip and a rear camera."
        }
    }

    nonisolated private static func hint(for mode: ARLabMode) -> String {
        switch mode {
        case .world: "Move the device slowly until planes appear, then tap a surface to place an entity; tap an entity to interact."
        case .face: "Look at the front camera; a sphere floats above the tracked face and the anchor list shows blend shapes."
        case .body: "Point the rear camera at a whole person; a sphere follows the body anchor's hip joint."
        case .image: "Point the camera at the reference pattern shown below (on another screen or printed)."
        }
    }

    #if canImport(ARKit) && canImport(RealityKit) && os(iOS)
    // MARK: Configuration

    private func makeConfiguration() -> ARConfiguration {
        switch mode {
        case .world:
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = planeDetection.arValue
            configuration.environmentTexturing = .automatic
            if sceneReconstruction {
                configuration.sceneReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) ? .meshWithClassification : .mesh
            }
            var semantics: ARConfiguration.FrameSemantics = []
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { semantics.insert(.sceneDepth) }
            if occlusion, ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) { semantics.insert(.personSegmentationWithDepth) }
            // Some combinations are not allowed together; fall back to people occlusion alone.
            if !ARWorldTrackingConfiguration.supportsFrameSemantics(semantics) { semantics.remove(.sceneDepth) }
            configuration.frameSemantics = semantics
            return configuration
        case .face:
            let configuration = ARFaceTrackingConfiguration()
            configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
            return configuration
        case .body:
            let configuration = ARBodyTrackingConfiguration()
            configuration.automaticSkeletonScaleEstimationEnabled = true
            configuration.planeDetection = planeDetection.arValue
            return configuration
        case .image:
            let configuration = ARImageTrackingConfiguration()
            configuration.trackingImages = arReferenceImage.map { [$0] } ?? []
            configuration.maximumNumberOfTrackedImages = 1
            return configuration
        }
    }

    private func rerunConfiguration() {
        guard isRunning, let arView else { return }
        arView.session.run(makeConfiguration())
        applyEnvironment(to: arView)
        output = "Configuration updated: planes \(planeDetection.rawValue.lowercased()), mesh \(sceneReconstruction ? "on" : "off"), occlusion \(occlusion ? "on" : "off")."
    }

    private func applyEnvironment(to view: ARView) {
        var understanding: ARView.Environment.SceneUnderstanding.Options = []
        var debug: ARView.DebugOptions = []
        if mode == .world, sceneReconstruction {
            understanding.formUnion([.physics, .collision])
            debug.insert(.showSceneUnderstanding)
        }
        if mode == .world, occlusion, sceneReconstruction { understanding.insert(.occlusion) }
        if showsDebug { debug.formUnion([.showFeaturePoints, .showAnchorOrigins, .showAnchorGeometry]) }
        view.environment.sceneUnderstanding.options = understanding
        view.debugOptions = debug
    }

    private func resetState() {
        trackedAnchors.removeAll()
        imageEntities.removeAll()
        placedAnchors.removeAll()
        placedCount = 0
        anchors = []
        stats = ARLabFrameStats()
        anchorsChanged = false
        windowStart = 0
        windowFrames = 0
        totalFrames = 0
    }

    // MARK: Entities

    /// Face and body modes attach an entity to RealityKit's automatic face or body anchor.
    private func addModeEntities(to view: ARView) {
        switch mode {
        case .face:
            let anchor = AnchorEntity(.face)
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [makeMaterial()])
            marker.position = [0, 0.14, 0]
            anchor.addChild(marker)
            view.scene.addAnchor(anchor)
        case .body:
            let anchor = AnchorEntity(.body)
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [makeMaterial()])
            anchor.addChild(marker)
            view.scene.addAnchor(anchor)
        case .world, .image:
            break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let view = arView else { return }
        let point = recognizer.location(in: view)
        if let entity = view.entity(at: point), let model = placedModel(containing: entity) {
            interact(with: model)
            return
        }
        guard mode == .world || mode == .body else {
            output = "Tap-to-place uses raycasts against planes, which \(mode.configurationName) does not provide."
            return
        }
        let results = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any)
        let fallback = results.isEmpty ? view.raycast(from: point, allowing: .estimatedPlane, alignment: .any) : results
        guard let result = fallback.first else {
            output = "The raycast hit no surface. Move the device until planes are detected (or turn on feature points), then tap a surface."
            return
        }
        place(at: result, fromExistingPlane: !results.isEmpty)
    }

    private func place(at result: ARRaycastResult, fromExistingPlane: Bool) {
        guard let view = arView else { return }
        let anchor = AnchorEntity(raycastResult: result)
        let model = makeModel()
        let halfHeight: Float = 0.05 // Both shapes are 10 cm tall.
        let horizontal = result.targetAlignment == .horizontal
        if physics && horizontal {
            // An invisible static floor at the hit point catches the dynamic body even without a LiDAR mesh.
            let floor = ModelEntity()
            floor.components.set(CollisionComponent(shapes: [.generateBox(width: 2, height: 0.002, depth: 2)]))
            floor.components.set(PhysicsBodyComponent(massProperties: .default, material: .generate(friction: 0.8, restitution: 0.3), mode: .static))
            anchor.addChild(floor)
            model.position = [0, 0.3, 0]
            model.components.set(PhysicsBodyComponent(massProperties: .default, material: .generate(friction: 0.6, restitution: 0.5), mode: .dynamic))
        } else {
            model.position = [0, halfHeight, 0]
        }
        anchor.addChild(model)
        view.scene.addAnchor(anchor)
        placedAnchors.append(anchor)
        placedCount = placedAnchors.count
        if !(physics && horizontal) { play(animation, on: model) }
        let target = fromExistingPlane ? "existing plane geometry" : "an estimated plane"
        let behaviour = physics && horizontal ? "dropped with a dynamic PhysicsBodyComponent" : animation == .none ? "placed" : "placed with a \(animation.rawValue.lowercased()) animation"
        let distance = simd_distance(result.worldTransform.columns.3, view.cameraTransform.matrix.columns.3)
        output = "\(shape.rawValue) \(behaviour) on \(target) (\(result.targetAlignment == .horizontal ? "horizontal" : result.targetAlignment == .vertical ? "vertical" : "any") alignment, \(ARLabFormat.meters(distance)) away)."
    }

    private func makeModel() -> ModelEntity {
        let mesh: MeshResource = shape == .box ? .generateBox(size: 0.1, cornerRadius: 0.008) : .generateSphere(radius: 0.05)
        let model = ModelEntity(mesh: mesh, materials: [makeMaterial()])
        model.name = "ATBPlaced"
        model.generateCollisionShapes(recursive: false)
        return model
    }

    private func makeMaterial() -> any RealityKit.Material {
        let tint = color.uiColor
        switch material {
        case .metallic: return SimpleMaterial(color: tint, roughness: 0.15, isMetallic: true)
        case .matte: return SimpleMaterial(color: tint, roughness: 0.9, isMetallic: false)
        case .unlit: return UnlitMaterial(color: tint)
        case .clearcoat:
            var pbr = PhysicallyBasedMaterial()
            pbr.baseColor = .init(tint: tint)
            pbr.roughness = 0.45
            pbr.metallic = 0.0
            pbr.clearcoat = 1.0
            pbr.clearcoatRoughness = 0.05
            return pbr
        }
    }

    private func play(_ animation: ARLabAnimation, on model: ModelEntity) {
        let start = model.transform
        var end = start
        let definition: FromToByAnimation<Transform>
        switch animation {
        case .none:
            return
        case .spin:
            end.rotation = simd_quatf(angle: 2 * .pi / 3, axis: [0, 1, 0]) * start.rotation
            definition = FromToByAnimation(from: start, to: end, duration: 1.2, timing: .linear, bindTarget: .transform, repeatMode: .cumulative)
        case .bounce:
            end.translation.y += 0.08
            definition = FromToByAnimation(from: start, to: end, duration: 0.5, timing: .easeInOut, bindTarget: .transform, repeatMode: .autoReverse)
        }
        do {
            model.playAnimation(try AnimationResource.generate(with: definition))
        } catch {
            output = "RealityKit could not build the animation: \(error.localizedDescription)"
        }
    }

    private func placedModel(containing entity: Entity) -> ModelEntity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == "ATBPlaced", let model = candidate as? ModelEntity { return model }
            current = candidate.parent
        }
        return nil
    }

    private func interact(with model: ModelEntity) {
        if let body = model.components[PhysicsBodyComponent.self], body.mode == .dynamic {
            model.applyLinearImpulse([0, 2, 0], relativeTo: nil)
            output = "Applied an upward impulse of 2 N·s to the dynamic body."
        } else {
            var target = model.transform
            target.scale *= 1.3
            let original = model.transform
            model.move(to: target, relativeTo: model.parent, duration: 0.15, timingFunction: .easeOut)
            Task {
                try? await Task.sleep(for: .milliseconds(160))
                model.move(to: original, relativeTo: model.parent, duration: 0.2, timingFunction: .easeIn)
            }
            output = "Tapped a static entity: RealityKit's entity(at:) hit test found it; it pulses with move(to:)."
        }
    }

    // MARK: Image tracking reference

    /// ARKit needs a reference image with dense, unique features. The app bundles no AR assets and its icon has
    /// too little detail, so a deterministic pattern is rendered at runtime and validated by ARKit.
    private func prepareReferenceImage() {
        guard arReferenceImage == nil else { return }
        let side: CGFloat = 1024
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            for shape in ARLabFormat.patternShapes() {
                let rect = CGRect(x: shape.rect.minX * side, y: shape.rect.minY * side, width: shape.rect.width * side, height: shape.rect.height * side)
                let path: UIBezierPath
                switch shape.kind {
                case .rectangle: path = UIBezierPath(rect: rect)
                case .ellipse: path = UIBezierPath(ovalIn: rect)
                case .triangle:
                    path = UIBezierPath()
                    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.close()
                }
                path.apply(CGAffineTransform(translationX: -rect.midX, y: -rect.midY).concatenating(CGAffineTransform(rotationAngle: shape.rotation)).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
                UIColor(hue: shape.hue, saturation: 0.85, brightness: shape.hue > 0.5 ? 0.35 : 0.8, alpha: 1).setFill()
                path.fill()
            }
            UIColor.black.setStroke()
            let border = UIBezierPath(rect: CGRect(x: 12, y: 12, width: side - 24, height: side - 24))
            border.lineWidth = 24
            border.stroke()
            let title = NSAttributedString(string: "APPLE TOOLBOX · AR", attributes: [.font: UIFont.systemFont(ofSize: 72, weight: .black), .foregroundColor: UIColor.black])
            title.draw(at: CGPoint(x: 60, y: side - 150))
        }
        guard let cgImage = rendered.cgImage else {
            referenceValidation = "The reference pattern could not be rendered."
            return
        }
        let reference = ARReferenceImage(cgImage, orientation: .up, physicalWidth: CGFloat(Self.referenceImageWidth))
        reference.name = "Apple Toolbox pattern"
        arReferenceImage = reference
        referenceImage = cgImage
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppleToolbox-AR-reference.png")
        if let data = rendered.pngData(), (try? data.write(to: url)) != nil { referenceImageURL = url }
        referenceValidation = "Validating…"
        reference.validate { @Sendable [weak self] error in
            let message = error.map { "Rejected: \($0.localizedDescription)" } ?? "Accepted by ARReferenceImage.validate"
            Task { @MainActor in self?.referenceValidation = message }
        }
    }

    // MARK: Frame and anchor bookkeeping (main queue)

    fileprivate func ingest(_ frame: ARFrame) {
        totalFrames += 1
        windowFrames += 1
        if windowStart == 0 { windowStart = frame.timestamp }
        let elapsed = frame.timestamp - windowStart
        guard elapsed >= 0.5 else { return }
        var stats = ARLabFrameStats()
        stats.trackingState = ARLabFormat.trackingState(frame.camera.trackingState)
        stats.worldMapping = mode == .world ? ARLabFormat.worldMapping(frame.worldMappingStatus) : "Not used by \(mode.configurationName)"
        stats.framesPerSecond = ARLabFormat.fps(frames: windowFrames, seconds: elapsed)
        stats.frames = totalFrames
        let resolution = frame.camera.imageResolution
        stats.cameraResolution = "\(Int(resolution.width)) × \(Int(resolution.height))"
        stats.featurePoints = frame.rawFeaturePoints?.points.count ?? 0
        if let light = frame.lightEstimate {
            stats.lightEstimate = String(format: "%.0f lm · %.0f K", light.ambientIntensity, light.ambientColorTemperature)
        }
        if let depth = frame.sceneDepth?.depthMap {
            stats.sceneDepth = "\(CVPixelBufferGetWidth(depth)) × \(CVPixelBufferGetHeight(depth)) LiDAR depth map"
        }
        stats.anchorCount = frame.anchors.count
        self.stats = stats
        windowStart = frame.timestamp
        windowFrames = 0
        if anchorsChanged { publishAnchors() }
    }

    fileprivate func track(_ changed: [ARAnchor], removed: Bool) {
        for anchor in changed {
            if removed {
                trackedAnchors[anchor.identifier] = nil
                imageEntities.removeValue(forKey: anchor.identifier)?.removeFromParent()
            } else {
                trackedAnchors[anchor.identifier] = anchor
            }
        }
        anchorsChanged = true
    }

    /// RealityKit anchors an entity to each detected reference image.
    fileprivate func attachImageEntity(to anchor: ARImageAnchor) {
        guard let view = arView, imageEntities[anchor.identifier] == nil else { return }
        let entity = AnchorEntity(anchor: anchor)
        let size = anchor.referenceImage.physicalSize
        let plate = ModelEntity(mesh: .generateBox(width: Float(size.width), height: 0.002, depth: Float(size.height)), materials: [UnlitMaterial(color: color.uiColor.withAlphaComponent(0.35))])
        let model = makeModel()
        model.position = [0, 0.05, 0]
        entity.addChild(plate)
        entity.addChild(model)
        view.scene.addAnchor(entity)
        imageEntities[anchor.identifier] = entity
        play(animation, on: model)
        output = "Detected “\(anchor.referenceImage.name ?? "reference image")” (estimated scale \(String(format: "%.2f", anchor.estimatedScaleFactor)))."
    }

    private func publishAnchors() {
        anchorsChanged = false
        anchors = trackedAnchors.values.map(Self.row(for:)).sorted { $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title }
    }

    private static func row(for anchor: ARAnchor) -> ARLabRow {
        let id = anchor.identifier.uuidString
        switch anchor {
        case let plane as ARPlaneAnchor:
            let alignment = plane.alignment == .horizontal ? "horizontal" : "vertical"
            return ARLabRow(id: id, title: "Plane (\(alignment))", detail: "\(ARLabFormat.classification(plane.classification)) · \(ARLabFormat.meters(plane.planeExtent.width)) × \(ARLabFormat.meters(plane.planeExtent.height))")
        case let mesh as ARMeshAnchor:
            return ARLabRow(id: id, title: "Mesh", detail: "\(mesh.geometry.vertices.count) vertices · \(mesh.geometry.faces.count) faces")
        case let face as ARFaceAnchor:
            let shapes: [(String, ARFaceAnchor.BlendShapeLocation)] = [("jawOpen", .jawOpen), ("eyeBlinkLeft", .eyeBlinkLeft), ("eyeBlinkRight", .eyeBlinkRight), ("mouthSmileLeft", .mouthSmileLeft)]
            let values = shapes.map { name, key in "\(name) \(String(format: "%.2f", face.blendShapes[key]?.floatValue ?? 0))" }.joined(separator: " · ")
            return ARLabRow(id: id, title: "Face", detail: "\(face.isTracked ? "Tracked" : "Not tracked") · \(face.blendShapes.count) blend shapes · \(values)")
        case let body as ARBodyAnchor:
            let joints = body.skeleton.jointModelTransforms.count
            let tracked = (0..<joints).filter { body.skeleton.isJointTracked($0) }.count
            return ARLabRow(id: id, title: "Body", detail: "\(body.isTracked ? "Tracked" : "Not tracked") · \(tracked)/\(joints) joints tracked · scale \(String(format: "%.2f", body.estimatedScaleFactor))")
        case let image as ARImageAnchor:
            return ARLabRow(id: id, title: "Image “\(image.referenceImage.name ?? "unnamed")”", detail: "\(image.isTracked ? "Tracked" : "Not tracked") · estimated scale \(String(format: "%.2f", image.estimatedScaleFactor))")
        case is AREnvironmentProbeAnchor:
            return ARLabRow(id: id, title: "Environment probe", detail: "Environment texture for reflections")
        default:
            return ARLabRow(id: id, title: "Anchor", detail: anchor.name ?? "Placed by a RealityKit raycast anchor")
        }
    }

    private static func supportRows() -> [ARLabRow] {
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        let best = formats.max { $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height }
        return [
            ARLabRow(id: "world", title: "World tracking", detail: "ARWorldTrackingConfiguration", supported: ARWorldTrackingConfiguration.isSupported),
            ARLabRow(id: "mesh", title: "Scene reconstruction", detail: ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) ? "Mesh with classification (LiDAR)" : "Needs a LiDAR Scanner", supported: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)),
            ARLabRow(id: "depth", title: "Scene depth", detail: "frameSemantics .sceneDepth (LiDAR)", supported: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)),
            ARLabRow(id: "people", title: "People occlusion", detail: "frameSemantics .personSegmentationWithDepth", supported: ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)),
            ARLabRow(id: "face", title: "Face tracking", detail: ARFaceTrackingConfiguration.isSupported ? "Up to \(ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces) face(s)" : "Needs a TrueDepth camera", supported: ARFaceTrackingConfiguration.isSupported),
            ARLabRow(id: "user-face", title: "Face tracking during world tracking", detail: "userFaceTrackingEnabled", supported: ARWorldTrackingConfiguration.supportsUserFaceTracking),
            ARLabRow(id: "body", title: "Body tracking", detail: "ARBodyTrackingConfiguration (A12+)", supported: ARBodyTrackingConfiguration.isSupported),
            ARLabRow(id: "body2d", title: "2D body detection", detail: "frameSemantics .bodyDetection", supported: ARWorldTrackingConfiguration.supportsFrameSemantics(.bodyDetection)),
            ARLabRow(id: "image", title: "Image tracking", detail: "ARImageTrackingConfiguration with a runtime reference image", supported: ARImageTrackingConfiguration.isSupported),
            ARLabRow(id: "geo", title: "Geo tracking", detail: "ARGeoTrackingConfiguration — also depends on location and coverage; not run by this lab", supported: ARGeoTrackingConfiguration.isSupported),
            ARLabRow(id: "object", title: "Object detection", detail: "Needs a scanned reference object; the app bundles none, so this lab does not run it", supported: nil),
            ARLabRow(id: "hand", title: "Hand tracking", detail: "ARKit hand tracking (HandTrackingProvider) is visionOS-only; on iPhone and iPad use the Vision Lab's hand pose", supported: false),
            ARLabRow(id: "formats", title: "Video formats", detail: best.map { "\(formats.count) · best \(Int($0.imageResolution.width)) × \(Int($0.imageResolution.height)) @ \($0.framesPerSecond) fps" } ?? "None reported", supported: nil),
        ]
    }
    #else
    private func rerunConfiguration() {}
    #endif
}

#if canImport(ARKit) && canImport(RealityKit) && os(iOS)
extension ARLabService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) { ingest(frame) }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        track(anchors, removed: false)
        for case let image as ARImageAnchor in anchors { attachImageEntity(to: image) }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { track(anchors, removed: false) }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) { track(anchors, removed: true) }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        stats.trackingState = ARLabFormat.trackingState(camera.trackingState)
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        let code = (error as? ARError).map { " (ARError code \($0.errorCode))" } ?? ""
        stop()
        status = .unavailable
        output = "ARSession failed\(code): \(error.localizedDescription)"
    }

    func sessionWasInterrupted(_ session: ARSession) {
        output = "The AR session was interrupted (for example the app moved to the background or the camera became unavailable)."
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        output = "The AR session interruption ended; tracking resumes and may need to relocalize."
    }
}

nonisolated extension ARLabPlaneDetection {
    var arValue: ARWorldTrackingConfiguration.PlaneDetection {
        switch self {
        case .none: []
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .both: [.horizontal, .vertical]
        }
    }
}

extension ARLabColor {
    var uiColor: UIColor {
        switch self {
        case .blue: .systemBlue
        case .red: .systemRed
        case .green: .systemGreen
        case .orange: .systemOrange
        case .purple: .systemPurple
        }
    }
}
#endif
