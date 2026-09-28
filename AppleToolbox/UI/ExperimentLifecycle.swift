import SwiftUI
import Combine

/// A service that runs a live session (sensor stream, scan, capture) which must end when the user leaves.
@MainActor
protocol StoppableExperiment: AnyObject {
    var isActive: Bool { get }
    func stop()
}

/// Owned by the detail view: run views register their live services, and the detail view stops
/// them when it disappears or when the user resets the experiment.
@MainActor
final class ExperimentLifecycle: ObservableObject {
    private var sessions: [ObjectIdentifier: () -> Void] = [:]

    func register(_ service: some StoppableExperiment) {
        sessions[ObjectIdentifier(service)] = { [weak service] in
            guard let service, service.isActive else { return }
            service.stop()
        }
    }

    func stopAll() {
        sessions.values.forEach { $0() }
    }

    func reset() {
        stopAll()
        sessions.removeAll()
    }
}

extension View {
    /// Registers a live service with the surrounding experiment so it stops when the experiment is left or reset.
    func experimentSession(_ service: some StoppableExperiment) -> some View {
        modifier(ExperimentSessionRegistration(service: service))
    }
}

private struct ExperimentSessionRegistration<Service: StoppableExperiment>: ViewModifier {
    let service: Service
    @EnvironmentObject private var lifecycle: ExperimentLifecycle

    func body(content: Content) -> some View {
        content.onAppear { lifecycle.register(service) }
    }
}

extension LocationExperimentService: StoppableExperiment { var isActive: Bool { isUpdating } }
extension MotionExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension NetworkExperimentService: StoppableExperiment { var isActive: Bool { isMonitoring } }
extension BluetoothExperimentService: StoppableExperiment { var isActive: Bool { isScanning } }
extension NFCExperimentService: StoppableExperiment { var isActive: Bool { isScanning } }
extension NearbyExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension MultipeerConnectivityExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension CameraVisionExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension AudioExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension SpeechExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension ARExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
