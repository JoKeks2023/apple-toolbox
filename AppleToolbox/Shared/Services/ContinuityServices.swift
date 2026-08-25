import Foundation
import Combine

#if canImport(WatchConnectivity) && !os(tvOS)
import WatchConnectivity
#endif

@MainActor
final class ContinuityExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Continuity is ready."
    #if canImport(WatchConnectivity) && !os(tvOS)
    private let session = WCSession.default
    #endif

    func activate() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported() else { output = "WatchConnectivity is not supported on this device."; return }
        session.delegate = self
        session.activate()
        output = "Activation requested. Reachability: \(session.isReachable)"
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }
}

#if canImport(WatchConnectivity) && !os(tvOS)
extension ContinuityExperimentService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        output = error.map { "Activation error: \($0.localizedDescription)" } ?? "Session activated: \(state.rawValue) · reachable: \(session.isReachable)"
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { output = "Session became inactive." }
    func sessionDidDeactivate(_ session: WCSession) { output = "Session deactivated." }
    #endif
}
#endif

#if canImport(AppIntents)
import AppIntents

struct ToolboxStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Apple Toolbox Status"
    static var description = IntentDescription("Returns a short status from Joris Apple Toolbox.")
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: "Joris Apple Toolbox is ready for experiments.")
    }
}
#endif
