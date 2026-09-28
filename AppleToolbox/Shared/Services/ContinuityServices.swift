import Foundation
import Combine

#if canImport(WatchConnectivity) && !os(tvOS)
import WatchConnectivity
#endif
#if canImport(UIKit)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// iPhone ↔ Apple Watch link. The same service runs in the iOS app and in the watch app,
/// so each side can ping its counterpart and answer incoming pings.
@MainActor
final class ContinuityExperimentService: NSObject, ObservableObject {
    static let shared = ContinuityExperimentService()

    @Published private(set) var output = "WatchConnectivity is ready."
    @Published private(set) var activation = "Not activated"
    @Published private(set) var isPaired: Bool?
    @Published private(set) var isCounterpartInstalled: Bool?
    @Published private(set) var isReachable = false
    @Published private(set) var lastMessage: String?

    static var deviceName: String {
        #if os(watchOS)
        WKInterfaceDevice.current().name
        #elseif canImport(UIKit)
        UIDevice.current.name
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    func activate() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported() else {
            activation = "Unsupported"
            output = "WatchConnectivity is not supported on this device (for example on iPad)."
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            refresh(from: session)
            output = "Session already active."
        } else {
            session.activate()
            output = "Activation requested…"
        }
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    func ping() {
        #if canImport(WatchConnectivity) && !os(tvOS)
        guard WCSession.isSupported() else { output = "WatchConnectivity is not supported on this device."; return }
        let session = WCSession.default
        guard session.activationState == .activated else { activate(); output = "Activate the session first, then ping again."; return }
        guard session.isReachable else {
            output = "Counterpart is not reachable. Open Apple Toolbox on the \(counterpartName) and keep it in the foreground."
            return
        }
        let sent = Date()
        output = "Ping sent to the \(counterpartName)…"
        session.sendMessage(["kind": "ping", "from": Self.deviceName], replyHandler: { [weak self] reply in
            let from = reply["from"] as? String ?? "counterpart"
            let milliseconds = Int(Date().timeIntervalSince(sent) * 1000)
            Task { @MainActor in
                self?.lastMessage = "Pong from \(from)"
                self?.output = "Round trip to \(from): \(milliseconds) ms"
            }
        }, errorHandler: { [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in self?.output = "Ping error: \(message)" }
        })
        #else
        output = "WatchConnectivity is not available on this platform."
        #endif
    }

    private var counterpartName: String {
        #if os(watchOS)
        "iPhone"
        #else
        "Apple Watch"
        #endif
    }

    #if canImport(WatchConnectivity) && !os(tvOS)
    private func refresh(from session: WCSession) {
        activation = session.activationState.title
        isReachable = session.isReachable
        #if os(iOS)
        isPaired = session.isPaired
        isCounterpartInstalled = session.isWatchAppInstalled
        #elseif os(watchOS)
        isPaired = true
        isCounterpartInstalled = session.isCompanionAppInstalled
        #endif
    }
    #endif
}

#if canImport(WatchConnectivity) && !os(tvOS)
extension ContinuityExperimentService: WCSessionDelegate {
    // WatchConnectivity calls the delegate on a background queue; UI state is updated on the main actor.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let message = error.map { "Activation error: \($0.localizedDescription)" } ?? "Session activated."
        Task { @MainActor [weak self] in
            self?.refresh(from: WCSession.default)
            self?.output = message
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refresh(from: WCSession.default) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let from = message["from"] as? String ?? "counterpart"
        replyHandler(["kind": "pong", "from": ContinuityExperimentService.replyName])
        Task { @MainActor [weak self] in
            self?.lastMessage = "Ping from \(from)"
            self?.output = "Answered a ping from \(from)."
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let from = message["from"] as? String ?? "counterpart"
        Task { @MainActor [weak self] in self?.lastMessage = "Message from \(from)" }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refresh(from: WCSession.default) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.output = "Session became inactive." }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch can connect.
        Task { @MainActor [weak self] in
            WCSession.default.activate()
            self?.output = "Session deactivated, re-activating for the current watch."
        }
    }
    #endif
}

extension ContinuityExperimentService {
    /// Read from the delegate queue when answering a ping, so it must not touch main-actor state.
    nonisolated static var replyName: String {
        #if os(watchOS)
        "Apple Watch"
        #else
        "iPhone"
        #endif
    }
}

private extension WCSessionActivationState {
    var title: String {
        switch self {
        case .activated: "Activated"
        case .inactive: "Inactive"
        case .notActivated: "Not activated"
        @unknown default: "Unknown"
        }
    }
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
