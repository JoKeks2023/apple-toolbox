import Foundation
import Combine

#if canImport(ARKit) && os(iOS)
import ARKit
#endif
#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif

@MainActor
final class ARExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "ARKit status is ready."
    @Published private(set) var isRunning = false
    #if canImport(ARKit) && os(iOS)
    private var session: ARSession?
    #endif

    func start() {
        #if canImport(ARKit) && os(iOS)
        guard ARWorldTrackingConfiguration.isSupported else { output = "ARKit world tracking is not supported on this device."; return }
        let configuration = ARWorldTrackingConfiguration()
        let sceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        if sceneDepth { configuration.frameSemantics.insert(.sceneDepth) }
        let session = ARSession()
        session.delegate = self
        session.run(configuration)
        self.session = session
        isRunning = true
        output = "ARKit world tracking started.\nScene depth: \(sceneDepth)\nMove the device to allow tracking to converge."
        #else
        output = "ARKit is not supported on this platform."
        #endif
    }

    func stop() {
        #if canImport(ARKit) && os(iOS)
        session?.pause(); session = nil; isRunning = false; output = "ARKit session stopped."
        #else
        output = "ARKit is not supported on this platform."
        #endif
    }
}

#if canImport(ARKit) && os(iOS)
extension ARExperimentService: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) { isRunning = false; output = "ARKit error: \(error.localizedDescription)" }
    func sessionWasInterrupted(_ session: ARSession) { output = "ARKit session interrupted." }
    func sessionInterruptionEnded(_ session: ARSession) { output = "ARKit session interruption ended." }
}
#endif

enum RoomPlanExperimentService {
    static func statusText() -> String {
        #if canImport(RoomPlan) && os(iOS)
        RoomCaptureSession.isSupported ? "RoomPlan is supported. A LiDAR-capable iPhone or iPad is required for the full room-capture workflow." : "RoomPlan is present, but this device does not support room capture."
        #else
        "RoomPlan is not supported on this platform."
        #endif
    }
}
