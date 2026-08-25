import Foundation
import Combine

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
import NearbyInteraction
#endif

@MainActor
final class NearbyExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Nearby Interaction is ready."
    @Published private(set) var isRunning = false

    #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
    private var session: NISession?
    #endif

    func start() {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            output = "Nearby Interaction is present, but precise distance measurement is not supported by this device."
            return
        }

        let session = NISession()
        session.delegate = self
        self.session = session
        isRunning = true
        let capabilities = NISession.deviceCapabilities
        output = "Session created.\nPrecise distance: \(capabilities.supportsPreciseDistanceMeasurement)\nDirection: \(capabilities.supportsDirectionMeasurement)\nCamera assistance: \(capabilities.supportsCameraAssistance)\n\nWaiting for a peer discovery token."
        #else
        output = "Nearby Interaction is not supported on this platform."
        #endif
    }

    func stop() {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        session?.invalidate()
        session = nil
        isRunning = false
        output = "Nearby Interaction session stopped."
        #else
        output = "Nearby Interaction is not supported on this platform."
        #endif
    }
}

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
extension NearbyExperimentService: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        let distance = object.distance.map { String(format: "%.2f m", $0) } ?? "unknown"
        let direction = object.direction.map { "\($0)" } ?? "unknown"
        output = "Nearby object detected.\nDistance: \(distance)\nDirection: \(direction)"
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        output = "Nearby object removed: \(reason)."
    }

    func sessionWasSuspended(_ session: NISession) {
        output = "Nearby Interaction session suspended."
    }

    func sessionSuspensionEnded(_ session: NISession) {
        output = "Nearby Interaction session resumed."
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        isRunning = false
        output = "Nearby Interaction error: \(error.localizedDescription)"
    }
}
#endif
