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
    /// True while a run view shows a full-screen cover: the detail view then disappears without the user leaving.
    var isCoverPresented = false

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

#if !os(macOS)
extension View {
    /// Use instead of `fullScreenCover` inside a run view. Presenting a cover takes the detail view off screen, and its
    /// `onDisappear` would otherwise stop the session the cover belongs to.
    func experimentFullScreenCover<Cover: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Cover) -> some View {
        modifier(ExperimentFullScreenCover(isPresented: isPresented, cover: content))
    }
}

private struct ExperimentFullScreenCover<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    let cover: () -> Cover
    @EnvironmentObject private var lifecycle: ExperimentLifecycle

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in lifecycle.isCoverPresented = presented }
            .fullScreenCover(isPresented: $isPresented, content: cover)
    }
}
#endif

private struct ExperimentSessionRegistration<Service: StoppableExperiment>: ViewModifier {
    let service: Service
    @EnvironmentObject private var lifecycle: ExperimentLifecycle

    func body(content: Content) -> some View {
        content.onAppear { lifecycle.register(service) }
    }
}

extension LocationExperimentService: StoppableExperiment {
    var isActive: Bool { isUpdating || monitoredRegion != nil || isMonitoringVisits || isMonitoringSignificantChanges }
}
extension MotionExperimentService: StoppableExperiment { var isActive: Bool { isRunning || isPedometerRunning || isAltimeterRunning } }
extension NetworkExperimentService: StoppableExperiment { var isActive: Bool { isMonitoring } }
extension BluetoothExperimentService: StoppableExperiment { var isActive: Bool { isScanning || isConnected } }
extension NFCExperimentService: StoppableExperiment { var isActive: Bool { isScanning } }
extension NFCInspectorService: StoppableExperiment {}
extension NFCCardEmulationService: StoppableExperiment {}
extension NearbyExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension MultipeerConnectivityExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension VisionLabService: StoppableExperiment {}
extension CameraLabService: StoppableExperiment {}
extension AudioExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension SpeechExperimentService: StoppableExperiment { var isActive: Bool { isRunning } }
extension ARLabService: StoppableExperiment {}
extension ShazamExperimentService: StoppableExperiment { var isActive: Bool { isListening } }
extension RoomPlanExperimentService: StoppableExperiment {}
