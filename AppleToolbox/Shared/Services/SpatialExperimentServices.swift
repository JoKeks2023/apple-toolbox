import Foundation
import Combine

#if canImport(RoomPlan) && os(iOS)
import RoomPlan
import AVFoundation
import UIKit
import simd
#endif

struct RoomScanRow: Identifiable, Equatable {
    let title: String
    let value: String
    var id: String { title }
}

struct RoomScanSummary: Equatable {
    let rows: [RoomScanRow]
    let objects: [RoomScanRow]
}

/// Presents a `RoomCaptureView`, turns the processed `CapturedRoom` into a summary and exports it as USDZ.
@MainActor
final class RoomPlanExperimentService: ObservableObject {
    enum CapturePhase { case idle, scanning, processing, finished }

    @Published private(set) var output: String
    @Published private(set) var status: ExperimentStatus
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var isPresentingCapture = false
    @Published private(set) var summary: RoomScanSummary?
    @Published private(set) var exportURL: URL?
    let isSupported: Bool
    /// Identifies the current capture so a late export from an earlier capture is discarded.
    private var captureID = UUID()
    #if canImport(RoomPlan) && os(iOS)
    private weak var captureView: RoomCaptureView?
    private var captureDelegate: RoomCaptureDelegate?
    #endif

    init() {
        #if canImport(RoomPlan) && os(iOS)
        let supported = RoomCaptureSession.isSupported
        isSupported = supported
        status = supported ? .available : .hardwareUnsupported
        output = supported ? "RoomPlan is supported. Start a capture and scan the room slowly, wall by wall." : "RoomCaptureSession.isSupported is false: this device has no LiDAR scanner, so RoomPlan cannot capture a room."
        #else
        isSupported = false
        status = .platformUnsupported
        output = "RoomPlan is only available on iPhone and iPad."
        #endif
    }

    var isActive: Bool { phase == .scanning || phase == .processing }

    func startCapture() {
        #if canImport(RoomPlan) && os(iOS)
        guard !isActive else { return }
        guard isSupported else { status = .hardwareUnsupported; output = "This device does not support RoomPlan room capture (LiDAR required)."; return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .video) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.startCapture() } else { self?.status = .permissionDenied; self?.output = "Camera permission was denied. RoomPlan needs the camera to scan the room." }
                }
            }
            return
        }
        removeExport()
        captureID = UUID()
        summary = nil
        status = .available
        phase = .scanning
        isPresentingCapture = true
        output = "Scanning. Move slowly around the room, then tap Done."
        #else
        output = "RoomPlan is only available on iPhone and iPad."
        #endif
    }

    /// Ends scanning; RoomPlan then processes the data and presents the final model.
    func finishScanning() {
        guard phase == .scanning else { return }
        #if canImport(RoomPlan) && os(iOS)
        captureView?.captureSession.stop()
        #endif
        phase = .processing
        output = "Processing the captured room…"
    }

    func cancelCapture() {
        guard phase != .idle || isPresentingCapture else { return }
        #if canImport(RoomPlan) && os(iOS)
        if phase == .scanning { captureView?.captureSession.stop() }
        #endif
        let wasCapturing = isActive
        releaseCapture()
        phase = .idle
        if wasCapturing { output = "Room capture cancelled. No room data was kept." }
    }

    func closeCapture() {
        releaseCapture()
        phase = .idle
    }

    func stop() { cancelCapture() }

    private func releaseCapture() {
        isPresentingCapture = false
        #if canImport(RoomPlan) && os(iOS)
        captureView = nil
        captureDelegate = nil
        #endif
    }

    private func removeExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
    }

    #if canImport(RoomPlan) && os(iOS)
    /// Creates the capture view shown full screen and starts the session.
    func makeCaptureView() -> UIView {
        let view = RoomCaptureView(frame: .zero)
        let delegate = RoomCaptureDelegate(service: self)
        view.delegate = delegate
        captureDelegate = delegate
        captureView = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    fileprivate func captureFailed(_ message: String) {
        guard isActive else { return }
        phase = .finished
        status = .unavailable
        output = "RoomPlan error: \(message)"
    }

    fileprivate func didPresent(_ room: CapturedRoom, errorMessage: String?) {
        // RoomPlan can also end the session on its own while scanning, so any active capture accepts the result.
        guard isActive else { return }
        phase = .finished
        if let errorMessage { status = .unavailable; output = "RoomPlan could not process the capture: \(errorMessage)"; return }
        summary = Self.summarize(room)
        let report = "Room captured: \(room.walls.count) walls, \(room.doors.count) doors, \(room.windows.count) windows, \(room.openings.count) openings, \(room.objects.count) objects."
        output = report + "\nExporting USDZ…"
        export(room, report: report)
    }

    private func export(_ room: CapturedRoom, report: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Room-\(Int(Date().timeIntervalSince1970)).usdz")
        let id = captureID
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do { try room.export(to: url, exportOptions: .parametric); return nil } catch { return error.localizedDescription }
            }.value
            guard id == captureID else { try? FileManager.default.removeItem(at: url); return }
            if let failure {
                output = report + "\nUSDZ export failed: \(failure)"
            } else {
                exportURL = url
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "unknown size"
                output = report + "\nUSDZ exported (\(size)): \(url.lastPathComponent)"
            }
        }
    }

    private static func summarize(_ room: CapturedRoom) -> RoomScanSummary {
        var rows: [RoomScanRow] = []
        let wallLength = room.walls.reduce(0) { $0 + $1.dimensions.x }
        let wallHeight = room.walls.map(\.dimensions.y).max() ?? 0
        rows.append(RoomScanRow(title: "Walls", value: room.walls.isEmpty ? "0" : "\(room.walls.count) · \(meters(wallLength)) total length"))
        let openDoors = room.doors.filter { if case .door(isOpen: true) = $0.category { true } else { false } }.count
        rows.append(RoomScanRow(title: "Doors", value: openDoors > 0 ? "\(room.doors.count) (\(openDoors) open)" : "\(room.doors.count)"))
        rows.append(RoomScanRow(title: "Windows", value: "\(room.windows.count)"))
        rows.append(RoomScanRow(title: "Openings", value: "\(room.openings.count)"))
        let floorArea = room.floors.reduce(Float(0)) { $0 + polygonArea($1.polygonCorners) }
        rows.append(RoomScanRow(title: "Floors", value: floorArea > 0 ? "\(room.floors.count) · \(String(format: "%.1f m²", floorArea))" : "\(room.floors.count)"))
        if let footprint = footprint(of: room.walls) {
            rows.append(RoomScanRow(title: "Overall size", value: "\(meters(footprint.x)) × \(meters(footprint.y)) × \(meters(wallHeight))"))
        }
        let sections = Dictionary(grouping: room.sections, by: { readable($0.label.rawValue) }).map { "\($0.key) (\($0.value.count))" }.sorted()
        if !sections.isEmpty { rows.append(RoomScanRow(title: "Room types", value: sections.joined(separator: ", "))) }
        let surfaces = room.walls + room.doors + room.windows + room.openings
        let lowConfidence = surfaces.count(where: { $0.confidence == .low }) + room.objects.count(where: { $0.confidence == .low })
        rows.append(RoomScanRow(title: "Low-confidence items", value: "\(lowConfidence)"))
        var objectCounts: [String: Int] = [:]
        for object in room.objects { objectCounts[readable(String(describing: object.category)), default: 0] += 1 }
        let objects = objectCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { RoomScanRow(title: $0.key, value: "\($0.value)") }
        return RoomScanSummary(rows: rows, objects: objects)
    }

    /// Width and depth of the wall outline, measured along the longest wall so a rotated room is not inflated.
    private static func footprint(of walls: [CapturedRoom.Surface]) -> SIMD2<Float>? {
        guard let longest = walls.max(by: { $0.dimensions.x < $1.dimensions.x }) else { return nil }
        let axis = simd_normalize(SIMD2(longest.transform.columns.0.x, longest.transform.columns.0.z))
        let normal = SIMD2(-axis.y, axis.x)
        var along: [Float] = [], across: [Float] = []
        for wall in walls {
            let center = SIMD2(wall.transform.columns.3.x, wall.transform.columns.3.z)
            let direction = SIMD2(wall.transform.columns.0.x, wall.transform.columns.0.z) * (wall.dimensions.x / 2)
            for point in [center + direction, center - direction] {
                along.append(simd_dot(point, axis))
                across.append(simd_dot(point, normal))
            }
        }
        guard let minAlong = along.min(), let maxAlong = along.max(), let minAcross = across.min(), let maxAcross = across.max() else { return nil }
        return SIMD2(maxAlong - minAlong, maxAcross - minAcross)
    }

    /// Area of a planar polygon in any orientation (Newell's method).
    private static func polygonArea(_ corners: [SIMD3<Float>]) -> Float {
        guard corners.count >= 3 else { return 0 }
        var normal = SIMD3<Float>.zero
        for index in corners.indices { normal += simd_cross(corners[index], corners[(index + 1) % corners.count]) }
        return simd_length(normal) / 2
    }

    private static func meters(_ value: Float) -> String { String(format: "%.2f m", value) }

    /// "washerDryer" → "Washer dryer".
    private static func readable(_ identifier: String) -> String {
        let spaced = identifier.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result += " " }
            result += character.lowercased()
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
    #endif
}

#if canImport(RoomPlan) && os(iOS)
/// RoomCaptureViewDelegate refines NSCoding, so a small NSObject receives the callbacks and hops to the service.
@objc(ATBRoomCaptureDelegate)
nonisolated final class RoomCaptureDelegate: NSObject, RoomCaptureViewDelegate {
    private weak var service: RoomPlanExperimentService?

    init(service: RoomPlanExperimentService) {
        self.service = service
        super.init()
    }

    required init?(coder: NSCoder) { nil }
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        guard let error else { return true }
        let message = error.localizedDescription
        let service = service
        Task { @MainActor in service?.captureFailed(message) }
        return false
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        let message = error?.localizedDescription
        let service = service
        Task { @MainActor in service?.didPresent(processedResult, errorMessage: message) }
    }
}
#endif
