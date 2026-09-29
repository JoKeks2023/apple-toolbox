import Foundation
import Combine
import CoreGraphics
import ImageIO
#if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
import Vision
import AVFoundation
import CoreImage
import CoreMedia
import Synchronization
#endif

// MARK: - Model (Sendable, produced off the main actor)

nonisolated enum VisionLabRequest: String, CaseIterable, Identifiable, Sendable {
    case barcodes = "Barcodes"
    case faces = "Face rectangles & landmarks"
    case bodyPose = "Human body pose"
    case handPose = "Hand pose"
    case classification = "Image classification"
    case document = "Document segmentation"
    case text = "Text recognition (OCR)"
    case tracking = "Object tracking"
    case animals = "Animal recognition"
    case humans = "Human rectangles"
    case saliency = "Objectness saliency"

    var id: String { rawValue }

    /// The Vision Swift API (iOS 18 / macOS 15) request type this option runs.
    var apiName: String {
        switch self {
        case .barcodes: "DetectBarcodesRequest"
        case .faces: "DetectFaceLandmarksRequest"
        case .bodyPose: "DetectHumanBodyPoseRequest"
        case .handPose: "DetectHumanHandPoseRequest"
        case .classification: "ClassifyImageRequest"
        case .document: "DetectDocumentSegmentationRequest"
        case .text: "RecognizeTextRequest"
        case .tracking: "TrackObjectRequest"
        case .animals: "RecognizeAnimalsRequest"
        case .humans: "DetectHumanRectanglesRequest"
        case .saliency: "GenerateObjectnessBasedSaliencyImageRequest"
        }
    }
}

nonisolated enum VisionLabSource: String, CaseIterable, Identifiable, Sendable {
    case camera = "Live camera"
    case photo = "Photo"
    var id: String { rawValue }
}

nonisolated enum VisionCameraPosition: String, CaseIterable, Identifiable, Sendable {
    case back = "Back"
    case front = "Front"
    var id: String { rawValue }
}

/// A shape to draw over the analyzed image. Points use Vision's normalized coordinates (origin bottom-left).
nonisolated struct VisionOverlayShape: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case polygon, polyline, points }
    enum Tint: Sendable { case primary, secondary, tracking, lost }

    let id = UUID()
    let kind: Kind
    let points: [CGPoint]
    var tint: Tint = .primary
    var label: String?
}

nonisolated struct VisionResultRow: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
}

nonisolated struct VisionAnalysis: Equatable, Sendable {
    var shapes: [VisionOverlayShape] = []
    var rows: [VisionResultRow] = []
    var summary = ""
    var isError = false
}

// MARK: - Geometry and formatting (pure, unit tested)

nonisolated enum VisionGeometry {
    /// The rectangle an aspect-fit image occupies inside a container.
    static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Vision normalized point (origin bottom-left) → view point (origin top-left) inside `imageRect`.
    static func viewPoint(_ normalized: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(x: imageRect.minX + normalized.x * imageRect.width, y: imageRect.minY + (1 - normalized.y) * imageRect.height)
    }

    /// View point → Vision normalized point, clamped to the image.
    static func normalizedPoint(_ viewPoint: CGPoint, in imageRect: CGRect) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        let x = (viewPoint.x - imageRect.minX) / imageRect.width
        let y = 1 - (viewPoint.y - imageRect.minY) / imageRect.height
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    /// Normalized rectangle spanned by a drag; a tap (tiny drag) becomes a square of `minimumSide` around the point.
    static func selectionRect(from start: CGPoint, to end: CGPoint, minimumSide: CGFloat = 0.15) -> CGRect {
        var rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        if rect.width < minimumSide / 3 || rect.height < minimumSide / 3 {
            rect = CGRect(x: end.x - minimumSide / 2, y: end.y - minimumSide / 2, width: minimumSide, height: minimumSide)
        }
        rect.origin.x = min(max(rect.minX, 0), 1 - min(rect.width, 1))
        rect.origin.y = min(max(rect.minY, 0), 1 - min(rect.height, 1))
        rect.size.width = min(rect.width, 1)
        rect.size.height = min(rect.height, 1)
        return rect
    }

    /// Corners of a normalized rectangle in drawing order.
    static func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
}

nonisolated enum VisionLabFormat {
    static func symbologyName(_ symbology: String) -> String {
        switch symbology {
        case "qr": "QR"
        case "microQR": "Micro QR"
        case "aztec": "Aztec"
        case "dataMatrix": "Data Matrix"
        case "pdf417": "PDF417"
        case "microPDF417": "Micro PDF417"
        case "ean8": "EAN-8"
        case "ean13": "EAN-13"
        case "upce": "UPC-E"
        case "itf14": "ITF-14"
        case "i2of5", "i2of5Checksum": "Interleaved 2 of 5"
        case "code39", "code39Checksum", "code39FullASCII", "code39FullASCIIChecksum": "Code 39"
        case "code93", "code93i": "Code 93"
        case "code128": "Code 128"
        case "codabar": "Codabar"
        case "gs1DataBar", "gs1DataBarExpanded", "gs1DataBarLimited": "GS1 DataBar"
        case "msiPlessey": "MSI Plessey"
        default: symbology
        }
    }

    /// "coffee_mug" → "coffee mug".
    static func classificationLabel(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    static func percent(_ confidence: Float) -> String { "\(Int((confidence * 100).rounded())) %" }

    /// Overlay label for a detection box, e.g. "Cat 92 %".
    static func detectionLabel(_ title: String, confidence: Float) -> String { "\(title) \(percent(confidence))" }

    /// A normalized bounding box (lower-left origin) as origin and size, e.g. "x 0.10 y 0.20 · 0.30 × 0.40".
    static func normalizedBox(_ rect: CGRect) -> String {
        String(format: "x %.2f y %.2f · %.2f × %.2f", rect.minX, rect.minY, rect.width, rect.height)
    }

    /// Animal labels sorted by confidence and joined, e.g. "Cat 92 % · Dog 5 %".
    static func rankedLabels(_ labels: [(identifier: String, confidence: Float)]) -> String {
        labels.sorted { $0.confidence > $1.confidence }.map { detectionLabel(classificationLabel($0.identifier), confidence: $0.confidence) }.joined(separator: " · ")
    }
}

#if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
// MARK: - Vision requests

nonisolated enum VisionLabAnalyzer {
    /// Runs one request on an upright image off the main actor and turns the observations into overlays and rows.
    @concurrent
    static func analyze(_ image: CGImage, request: VisionLabRequest, live: Bool, tracker: TrackObjectRequest?) async -> VisionAnalysis {
        do {
            switch request {
            case .barcodes: return try await barcodes(image)
            case .faces: return try await faces(image)
            case .bodyPose: return try await bodyPose(image)
            case .handPose: return try await handPose(image)
            case .classification: return try await classification(image)
            case .document: return try await document(image)
            case .text: return try await text(image, live: live)
            case .tracking: return try await track(image, tracker: tracker)
            case .animals: return try await animals(image)
            case .humans: return try await humans(image)
            case .saliency: return try await saliency(image)
            }
        } catch {
            return VisionAnalysis(summary: "\(request.apiName) failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func barcodes(_ image: CGImage) async throws -> VisionAnalysis {
        let observations = try await DetectBarcodesRequest().perform(on: image)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No barcode in this image." : "\(observations.count) barcode(s).")
        for barcode in observations {
            let name = VisionLabFormat.symbologyName(String(describing: barcode.symbology))
            analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: [barcode.bottomLeft, barcode.bottomRight, barcode.topRight, barcode.topLeft].map(\.cgPoint), label: name))
            let payload = barcode.payloadString ?? barcode.payloadData.map { "\($0.count) bytes of binary payload" } ?? "No payload"
            analysis.rows.append(VisionResultRow(title: name + (barcode.isGS1DataCarrier ? " · GS1" : ""), detail: payload))
        }
        return analysis
    }

    private static func faces(_ image: CGImage) async throws -> VisionAnalysis {
        let observations = try await DetectFaceLandmarksRequest().perform(on: image)
        let size = CGSize(width: image.width, height: image.height)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No face in this image." : "\(observations.count) face(s).")
        for (index, face) in observations.enumerated() {
            analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: VisionGeometry.corners(of: face.boundingBox.cgRect), label: "Face \(index + 1)"))
            var landmarkCount = 0
            if let landmarks = face.landmarks {
                let regions = [landmarks.faceContour, landmarks.leftEye, landmarks.rightEye, landmarks.leftEyebrow, landmarks.rightEyebrow, landmarks.nose,
                               landmarks.noseCrest, landmarks.medianLine, landmarks.outerLips, landmarks.innerLips, landmarks.leftPupil, landmarks.rightPupil]
                for region in regions where !region.points.isEmpty {
                    landmarkCount += region.points.count
                    let points = region.pointsInImageCoordinates(size, origin: .lowerLeft).map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
                    let kind: VisionOverlayShape.Kind = switch region.pointsClassification {
                    case .closedPath: .polygon
                    case .openPath: .polyline
                    default: .points
                    }
                    analysis.shapes.append(VisionOverlayShape(kind: kind, points: points, tint: .secondary))
                }
            }
            let angles = String(format: "roll %.0f° · yaw %.0f° · pitch %.0f°", face.roll.converted(to: .degrees).value, face.yaw.converted(to: .degrees).value, face.pitch.converted(to: .degrees).value)
            analysis.rows.append(VisionResultRow(title: "Face \(index + 1)", detail: "\(VisionLabFormat.percent(face.confidence)) · \(landmarkCount) landmark points · \(angles)"))
        }
        return analysis
    }

    private static func bodyPose(_ image: CGImage) async throws -> VisionAnalysis {
        let observations = try await DetectHumanBodyPoseRequest().perform(on: image)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No person in this image." : "\(observations.count) person(s).")
        for (index, person) in observations.enumerated() {
            let joints = person.allJoints().filter { $0.value.confidence > 0.1 }
            analysis.shapes += skeleton(joints: joints, bones: bodyBones)
            let mean = joints.isEmpty ? 0 : joints.values.map(\.confidence).reduce(0, +) / Float(joints.count)
            analysis.rows.append(VisionResultRow(title: "Person \(index + 1)", detail: "\(joints.count) of \(person.availableJointNames.count) joints · mean joint confidence \(VisionLabFormat.percent(mean)) · observation \(VisionLabFormat.percent(person.confidence))"))
        }
        return analysis
    }

    private static func handPose(_ image: CGImage) async throws -> VisionAnalysis {
        var request = DetectHumanHandPoseRequest()
        request.maximumHandCount = 4
        let observations = try await request.perform(on: image)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No hand in this image." : "\(observations.count) hand(s).")
        for (index, hand) in observations.enumerated() {
            let joints = hand.allJoints().filter { $0.value.confidence > 0.1 }
            analysis.shapes += skeleton(joints: joints, bones: handBones)
            let side = switch hand.chirality {
            case .left?: "Left hand"
            case .right?: "Right hand"
            default: "Hand \(index + 1)"
            }
            let mean = joints.isEmpty ? 0 : joints.values.map(\.confidence).reduce(0, +) / Float(joints.count)
            analysis.rows.append(VisionResultRow(title: side, detail: "\(joints.count) of \(hand.availableJointNames.count) joints · mean joint confidence \(VisionLabFormat.percent(mean))"))
        }
        return analysis
    }

    private static func classification(_ image: CGImage) async throws -> VisionAnalysis {
        let observations = try await ClassifyImageRequest().perform(on: image)
        let top = observations.filter { $0.confidence >= 0.01 }.sorted { $0.confidence > $1.confidence }.prefix(8)
        var analysis = VisionAnalysis(summary: top.first.map { "Top label: \(VisionLabFormat.classificationLabel($0.identifier)) (\(VisionLabFormat.percent($0.confidence)))." } ?? "No label above 1 % confidence.")
        analysis.rows = top.map { VisionResultRow(title: VisionLabFormat.classificationLabel($0.identifier), detail: VisionLabFormat.percent($0.confidence)) }
        analysis.rows.append(VisionResultRow(title: "Taxonomy", detail: "\(observations.count) labels scored"))
        return analysis
    }

    private static func animals(_ image: CGImage) async throws -> VisionAnalysis {
        let observations = try await RecognizeAnimalsRequest().perform(on: image)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No cat or dog recognized. RecognizeAnimalsRequest only knows cats and dogs." : "\(observations.count) animal(s).")
        for (index, animal) in observations.enumerated() {
            let top = animal.labels.max { $0.confidence < $1.confidence }
            let name = top.map { VisionLabFormat.classificationLabel($0.identifier) } ?? "Animal"
            let box = animal.boundingBox.cgRect
            analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: VisionGeometry.corners(of: box), label: VisionLabFormat.detectionLabel(name, confidence: top?.confidence ?? animal.confidence)))
            let labels = VisionLabFormat.rankedLabels(animal.labels.map { (identifier: $0.identifier, confidence: $0.confidence) })
            analysis.rows.append(VisionResultRow(title: "Animal \(index + 1) · \(VisionLabFormat.percent(animal.confidence))", detail: "\(labels)\n\(VisionLabFormat.normalizedBox(box))"))
        }
        return analysis
    }

    private static func humans(_ image: CGImage) async throws -> VisionAnalysis {
        var request = DetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        let observations = try await request.perform(on: image)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No person detected." : "\(observations.count) person(s).")
        for (index, human) in observations.enumerated() {
            let box = human.boundingBox.cgRect
            let extent = human.isUpperBodyOnly ? "upper body" : "full body"
            analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: VisionGeometry.corners(of: box), label: VisionLabFormat.detectionLabel("Person \(index + 1)", confidence: human.confidence)))
            analysis.rows.append(VisionResultRow(title: "Person \(index + 1) · \(extent)", detail: "Confidence \(VisionLabFormat.percent(human.confidence)) · \(VisionLabFormat.normalizedBox(box))"))
        }
        return analysis
    }

    private static func saliency(_ image: CGImage) async throws -> VisionAnalysis {
        let observation = try await GenerateObjectnessBasedSaliencyImageRequest().perform(on: image)
        let objects = observation.salientObjects
        var analysis = VisionAnalysis(summary: objects.isEmpty ? "No salient object found." : "\(objects.count) salient object region(s).")
        for (index, object) in objects.enumerated() {
            let corners = [object.bottomLeft, object.bottomRight, object.topRight, object.topLeft].map(\.cgPoint)
            analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: corners, tint: .secondary, label: VisionLabFormat.detectionLabel("Object \(index + 1)", confidence: object.confidence)))
            let box = CGRect(x: corners.map(\.x).min() ?? 0, y: corners.map(\.y).min() ?? 0,
                             width: (corners.map(\.x).max() ?? 0) - (corners.map(\.x).min() ?? 0), height: (corners.map(\.y).max() ?? 0) - (corners.map(\.y).min() ?? 0))
            analysis.rows.append(VisionResultRow(title: "Object \(index + 1)", detail: "Confidence \(VisionLabFormat.percent(object.confidence)) · \(VisionLabFormat.normalizedBox(box))"))
        }
        let heatMap = observation.heatMap.size
        analysis.rows.append(VisionResultRow(title: "Saliency heat map", detail: "\(Int(heatMap.width)) × \(Int(heatMap.height)) · objectness-based"))
        return analysis
    }

    private static func document(_ image: CGImage) async throws -> VisionAnalysis {
        guard let document = try await DetectDocumentSegmentationRequest().perform(on: image) else {
            return VisionAnalysis(summary: "No document detected.")
        }
        var analysis = VisionAnalysis(summary: "Document detected (\(VisionLabFormat.percent(document.confidence))).")
        analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: [document.bottomLeft, document.bottomRight, document.topRight, document.topLeft].map(\.cgPoint), label: "Document"))
        let mask = document.globalSegmentationMask.size
        analysis.rows = [
            VisionResultRow(title: "Confidence", detail: VisionLabFormat.percent(document.confidence)),
            VisionResultRow(title: "Corners", detail: [document.topLeft, document.topRight, document.bottomRight, document.bottomLeft].map { String(format: "(%.2f, %.2f)", $0.x, $0.y) }.joined(separator: " ")),
            VisionResultRow(title: "Segmentation mask", detail: "\(Int(mask.width)) × \(Int(mask.height))"),
        ]
        return analysis
    }

    private static func text(_ image: CGImage, live: Bool) async throws -> VisionAnalysis {
        var request = RecognizeTextRequest()
        request.recognitionLevel = live ? .fast : .accurate
        request.usesLanguageCorrection = !live
        let observations = try await request.perform(on: image)
        var analysis = VisionAnalysis(summary: observations.isEmpty ? "No text recognized." : "\(observations.count) text line(s), \(live ? "fast" : "accurate") recognition.")
        for observation in observations {
            analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: [observation.bottomLeft, observation.bottomRight, observation.topRight, observation.topLeft].map(\.cgPoint)))
        }
        analysis.rows = observations.prefix(12).compactMap { observation in
            observation.topCandidates(1).first.map { VisionResultRow(title: $0.string, detail: VisionLabFormat.percent($0.confidence)) }
        }
        return analysis
    }

    private static func track(_ image: CGImage, tracker: TrackObjectRequest?) async throws -> VisionAnalysis {
        guard let tracker else {
            return VisionAnalysis(summary: "Drag a rectangle around an object in the live image to start TrackObjectRequest.")
        }
        guard let observation = try await tracker.perform(on: image) else {
            return VisionAnalysis(summary: "The tracker returned no observation for this frame.")
        }
        let lost = observation.confidence < 0.3
        var analysis = VisionAnalysis(summary: lost ? "Low confidence — the object is probably lost. Drag a new rectangle." : "Tracking the selected object.")
        analysis.shapes.append(VisionOverlayShape(kind: .polygon, points: VisionGeometry.corners(of: observation.boundingBox.cgRect), tint: lost ? .lost : .tracking, label: VisionLabFormat.percent(observation.confidence)))
        let box = observation.boundingBox.cgRect
        analysis.rows = [
            VisionResultRow(title: "Confidence", detail: VisionLabFormat.percent(observation.confidence)),
            VisionResultRow(title: "Bounding box", detail: String(format: "x %.2f · y %.2f · %.2f × %.2f", box.minX, box.minY, box.width, box.height)),
        ]
        return analysis
    }

    private static func skeleton<Name: Hashable>(joints: [Name: Joint], bones: [(Name, Name)]) -> [VisionOverlayShape] {
        var shapes = bones.compactMap { bone -> VisionOverlayShape? in
            guard let from = joints[bone.0], let to = joints[bone.1] else { return nil }
            return VisionOverlayShape(kind: .polyline, points: [from.location.cgPoint, to.location.cgPoint], tint: .secondary)
        }
        shapes.append(VisionOverlayShape(kind: .points, points: joints.values.map(\.location.cgPoint)))
        return shapes
    }

    private static let bodyBones: [(HumanBodyPoseObservation.JointName, HumanBodyPoseObservation.JointName)] = [
        (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar), (.nose, .neck),
        (.neck, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.neck, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root), (.root, .leftHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.root, .rightHip), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    private static let handBones: [(HumanHandPoseObservation.JointName, HumanHandPoseObservation.JointName)] = [
        (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
        (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
        (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
        (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
        (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
    ]

    /// Decodes a picked photo upright (EXIF orientation applied), capped so Vision stays responsive.
    @concurrent
    static func uprightImage(from data: Data, maxPixelSize: Int = 2048) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

nonisolated struct VisionFrameConfiguration: Sendable {
    var request: VisionLabRequest
    var tracker: TrackObjectRequest?
    var generation: Int
}

/// Receives camera frames on its own queue, analyzes one frame at a time and drops frames that arrive meanwhile.
nonisolated final class VisionFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "apple-toolbox.vision-lab.frames")
    /// Set once on the main actor before frames arrive.
    weak var service: VisionLabService?
    private let busy = Mutex(false)
    private let configuration = Mutex(VisionFrameConfiguration(request: .barcodes, tracker: nil, generation: 0))
    private let context = CIContext()

    func configure(_ newValue: VisionFrameConfiguration) {
        configuration.withLock { $0 = newValue }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let acquired = busy.withLock { isBusy -> Bool in
            if isBusy { return false }
            isBusy = true
            return true
        }
        guard acquired else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              case let frame = CIImage(cvPixelBuffer: pixelBuffer),
              let image = context.createCGImage(frame, from: frame.extent) else {
            busy.withLock { $0 = false }
            return
        }
        let current = configuration.withLock { $0 }
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            let analysis = await VisionLabAnalyzer.analyze(image, request: current.request, live: true, tracker: current.tracker)
            let elapsed = start.duration(to: clock.now)
            let service = self.service
            await MainActor.run { service?.didAnalyzeFrame(image, analysis: analysis, latency: elapsed, generation: current.generation) }
            // Caps the rate at about 12 analyzed frames per second so the list stays responsive.
            if elapsed < .milliseconds(80) { try? await Task.sleep(for: .milliseconds(80) - elapsed) }
            self.busy.withLock { $0 = false }
        }
    }
}
#endif

// MARK: - Service

/// Vision Lab: runs Vision's Swift requests on live camera frames or a picked photo and draws the observations.
@MainActor
final class VisionLabService: ObservableObject {
    @Published private(set) var request: VisionLabRequest = .barcodes
    @Published private(set) var source: VisionLabSource = .camera
    @Published private(set) var cameraPosition: VisionCameraPosition = .back
    @Published private(set) var isRunning = false
    @Published private(set) var image: CGImage?
    @Published private(set) var analysis = VisionAnalysis()
    @Published private(set) var output: String
    @Published private(set) var status: ExperimentStatus
    @Published private(set) var framesAnalyzed = 0
    @Published private(set) var latencyMilliseconds: Double?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isTracking = false

    var isError: Bool { analysis.isError || [.unavailable, .permissionDenied, .hardwareUnsupported, .platformUnsupported].contains(status) }

    private var photo: CGImage?
    /// Discards results that belong to an earlier request, source or tracker.
    private var generation = 0

    #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    // Configured, started and stopped only on sessionQueue (startRunning blocks).
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let frames = VisionFrameReceiver()
    private let sessionQueue = DispatchQueue(label: "apple-toolbox.vision-lab.session")
    private var tracker: TrackObjectRequest?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    #endif

    init() {
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        status = .available
        output = "Choose a Vision request, then start the live camera or pick a photo. Nothing leaves the device."
        frames.service = self
        #else
        status = .platformUnsupported
        output = "The Vision Lab needs a camera or the system photo picker; Apple TV and Apple Watch offer neither to this app."
        #endif
    }

    var isActive: Bool { isRunning }

    func setRequest(_ newRequest: VisionLabRequest) {
        guard newRequest != request else { return }
        request = newRequest
        restartAnalysis()
    }

    func setSource(_ newSource: VisionLabSource) {
        guard newSource != source else { return }
        if isRunning { stop() }
        source = newSource
        image = newSource == .photo ? photo : nil
        restartAnalysis()
    }

    func setCameraPosition(_ position: VisionCameraPosition) {
        guard position != cameraPosition else { return }
        cameraPosition = position
        if isRunning {
            stop()
            start()
        }
    }

    private func restartAnalysis() {
        generation += 1
        framesAnalyzed = 0
        latencyMilliseconds = nil
        analysis = VisionAnalysis()
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        tracker = nil
        isTracking = false
        frames.configure(VisionFrameConfiguration(request: request, tracker: nil, generation: generation))
        if source == .photo {
            analyzePhoto()
        } else if request == .tracking {
            output = isRunning ? "Drag a rectangle around an object in the live image; TrackObjectRequest follows it frame by frame." : "Start the live camera, then drag a rectangle around an object to track it."
        } else {
            output = isRunning ? "\(request.apiName) now runs on live frames." : "Start the live camera to run \(request.apiName) on each frame."
        }
        #endif
    }

    // MARK: Live camera

    func start() {
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isRunning else { return }
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
        #if os(iOS)
        let position: AVCaptureDevice.Position = cameraPosition == .back ? .back : .front
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) ?? AVCaptureDevice.default(for: .video)
        #else
        let device = AVCaptureDevice.default(for: .video)
        #endif
        guard let device else {
            status = .hardwareUnsupported
            output = "No camera is available. Pick a photo instead — every request except object tracking works on a single image."
            return
        }
        source = .camera
        isRunning = true
        status = .available
        image = nil
        restartAnalysis()
        output = "Starting \(device.localizedName)…"
        followDeviceRotation(of: device)
        nonisolated(unsafe) let captureDevice = device // Only used on sessionQueue from here on.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let failure = configureAndStart(device: captureDevice)
            Task { @MainActor in
                guard self.isRunning else { return }
                if let failure {
                    self.stop()
                    self.status = .unavailable
                    self.output = "Camera error: \(failure)"
                } else {
                    self.restartAnalysis()
                }
            }
        }
        #endif
    }

    func stop() {
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        rotationObservation = nil
        rotationCoordinator = nil
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.stopRunning()
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
        }
        tracker = nil
        #endif
        guard isRunning else { return }
        isRunning = false
        isTracking = false
        generation += 1
        output = "Live analysis stopped after \(framesAnalyzed) analyzed frame(s)."
    }

    /// Starts TrackObjectRequest on a rectangle chosen in the live image (Vision normalized coordinates).
    func startTracking(_ rect: CGRect) {
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard isRunning, request == .tracking else { return }
        let observation = DetectedObjectObservation(boundingBox: NormalizedRect(normalizedRect: rect))
        let tracker = TrackObjectRequest(detectedObject: observation)
        self.tracker = tracker
        generation += 1
        framesAnalyzed = 0
        isTracking = true
        frames.configure(VisionFrameConfiguration(request: .tracking, tracker: tracker, generation: generation))
        output = String(format: "Tracking the rectangle at x %.2f, y %.2f (%.2f × %.2f) with TrackObjectRequest.", rect.minX, rect.minY, rect.width, rect.height)
        #endif
    }

    func stopTracking() {
        guard isTracking else { return }
        restartAnalysis()
    }

    // MARK: Photo

    func usePhoto(_ data: Data) {
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        if isRunning { stop() }
        source = .photo
        isAnalyzing = true
        output = "Decoding the photo…"
        Task {
            guard let decoded = await VisionLabAnalyzer.uprightImage(from: data) else {
                isAnalyzing = false
                output = "ImageIO could not decode the picked item as an image."
                return
            }
            photo = decoded
            image = decoded
            restartAnalysis()
        }
        #endif
    }

    func photoLoadFailed(_ message: String) {
        isAnalyzing = false
        output = "The photo could not be loaded: \(message)"
    }

    private func analyzePhoto() {
        #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard let photo else {
            isAnalyzing = false
            output = "Pick a photo to run \(request.apiName) on it."
            return
        }
        guard request != .tracking else {
            isAnalyzing = false
            analysis = VisionAnalysis(summary: "Object tracking needs consecutive frames. Switch the source to Live camera.")
            output = analysis.summary
            return
        }
        let id = generation
        let request = request
        isAnalyzing = true
        output = "Running \(request.apiName) on the photo…"
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            let result = await VisionLabAnalyzer.analyze(photo, request: request, live: false, tracker: nil)
            guard id == generation else { return }
            isAnalyzing = false
            analysis = result
            latencyMilliseconds = Self.milliseconds(start.duration(to: clock.now))
            framesAnalyzed = 1
            output = "\(request.apiName) on a \(photo.width) × \(photo.height) photo: \(result.summary)"
        }
        #endif
    }

    // MARK: Frame results

    fileprivate func didAnalyzeFrame(_ frame: CGImage, analysis result: VisionAnalysis, latency: Duration, generation id: Int) {
        guard id == generation, isRunning else { return }
        image = frame
        analysis = result
        framesAnalyzed += 1
        latencyMilliseconds = Self.milliseconds(latency)
        if result.isError || request == .tracking || framesAnalyzed == 1 { output = result.summary }
    }

    private func reportDenied() {
        status = .permissionDenied
        output = "Camera access is denied or restricted. Allow it in Settings › Privacy & Security › Camera, or pick a photo instead."
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    #if canImport(Vision) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    /// Runs on sessionQueue; returns an error description or nil when the session is running.
    nonisolated private func configureAndStart(device: AVCaptureDevice) -> String? {
        session.beginConfiguration()
        for preset in [AVCaptureSession.Preset.hd1280x720, .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            break
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return "The capture session cannot accept the camera input or the video data output."
            }
            session.addInput(input)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(frames, queue: frames.queue)
            session.addOutput(videoOutput)
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            return error.localizedDescription
        }
        session.startRunning()
        return session.isRunning ? nil : "AVCaptureSession did not start running."
    }

    /// Rotates delivered frames so they are upright for Vision, following the device orientation.
    private func followDeviceRotation(of device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { @Sendable [weak self] coordinator, _ in
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
