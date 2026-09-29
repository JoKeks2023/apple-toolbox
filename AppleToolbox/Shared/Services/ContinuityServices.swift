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

/// Keys and kinds of the messages Apple Toolbox sends over WatchConnectivity.
nonisolated enum WatchLinkMessage {
    static let kindKey = "kind"
    static let fromKey = "from"
    static let tokenKey = "token"
    static let errorKey = "error"

    static let ping = "ping"
    static let pong = "pong"
    /// The watch sends its archived `NIDiscoveryToken`; the iPhone answers with its own under `tokenKey`.
    static let nearbyToken = "nearby-token"
    /// The watch ended its Nearby Interaction session, so the iPhone ends its side too.
    static let nearbyStop = "nearby-stop"
}

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
    /// Round trip of the last answered ping, in milliseconds.
    @Published private(set) var lastRoundTripMilliseconds: Int?

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
        session.sendMessage([WatchLinkMessage.kindKey: WatchLinkMessage.ping, WatchLinkMessage.fromKey: Self.deviceName], replyHandler: { @Sendable [weak self] reply in
            let from = reply[WatchLinkMessage.fromKey] as? String ?? "counterpart"
            let milliseconds = Int(Date().timeIntervalSince(sent) * 1000)
            Task { @MainActor in
                self?.lastMessage = "Pong from \(from)"
                self?.lastRoundTripMilliseconds = milliseconds
                self?.output = "Round trip to \(from): \(milliseconds) ms"
            }
        }, errorHandler: { @Sendable [weak self] error in
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

    #if os(watchOS)
    // MARK: Nearby Interaction token exchange (watch side)

    /// Sends this watch's archived Nearby Interaction discovery token to the iPhone and returns the iPhone's token.
    /// watchOS has no MultipeerConnectivity, so WatchConnectivity carries the tokens, as in Apple's watchOS sample.
    func exchangeNearbyToken(_ token: Data) async throws -> Data {
        guard WCSession.isSupported() else { throw ExperimentServiceError.unavailable("WatchConnectivity is not supported on this device.") }
        let session = WCSession.default
        guard session.activationState == .activated else {
            activate()
            throw ExperimentServiceError.unavailable("The WatchConnectivity session is not active yet. Try again in a moment.")
        }
        guard session.isReachable else {
            throw ExperimentServiceError.unavailable("The iPhone is not reachable. Open Apple Toolbox on the paired iPhone, keep it in the foreground, then try again.")
        }
        let message: [String: Any] = [WatchLinkMessage.kindKey: WatchLinkMessage.nearbyToken, WatchLinkMessage.tokenKey: token,
                                      WatchLinkMessage.fromKey: Self.deviceName]
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { @Sendable reply in
                if let token = reply[WatchLinkMessage.tokenKey] as? Data {
                    continuation.resume(returning: token)
                } else {
                    let reason = reply[WatchLinkMessage.errorKey] as? String ?? "The iPhone answered without a discovery token."
                    continuation.resume(throwing: ExperimentServiceError.unavailable(reason))
                }
            }, errorHandler: { @Sendable error in
                continuation.resume(throwing: error)
            })
        }
    }

    /// Tells the iPhone to end its side of the ranging session; best effort, only while it is reachable.
    func endNearbyRanging() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchLinkMessage.kindKey: WatchLinkMessage.nearbyStop], replyHandler: nil, errorHandler: nil)
    }
    #endif

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
        let from = message[WatchLinkMessage.fromKey] as? String ?? "counterpart"
        #if os(iOS) && canImport(NearbyInteraction)
        if message[WatchLinkMessage.kindKey] as? String == WatchLinkMessage.nearbyToken, let token = message[WatchLinkMessage.tokenKey] as? Data {
            // WatchConnectivity lets the reply come later; it is sent exactly once, after the main actor set up the session.
            nonisolated(unsafe) let replyHandler = replyHandler
            Task { @MainActor [weak self] in
                do {
                    let ownToken = try WatchNearbyResponder.shared.respond(toWatchToken: token, from: from)
                    replyHandler([WatchLinkMessage.tokenKey: ownToken])
                    self?.lastMessage = "Nearby token from \(from)"
                } catch {
                    replyHandler([WatchLinkMessage.errorKey: error.localizedDescription])
                    self?.lastMessage = "Nearby token from \(from) rejected"
                }
            }
            return
        }
        #endif
        replyHandler([WatchLinkMessage.kindKey: WatchLinkMessage.pong, WatchLinkMessage.fromKey: ContinuityExperimentService.replyName])
        Task { @MainActor [weak self] in
            self?.lastMessage = "Ping from \(from)"
            self?.output = "Answered a ping from \(from)."
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let from = message[WatchLinkMessage.fromKey] as? String ?? "counterpart"
        let kind = message[WatchLinkMessage.kindKey] as? String
        Task { @MainActor [weak self] in
            #if os(iOS) && canImport(NearbyInteraction)
            if kind == WatchLinkMessage.nearbyStop {
                WatchNearbyResponder.shared.stop(reason: "The watch ended ranging.")
                self?.lastMessage = "Nearby ranging ended by the watch"
                return
            }
            #endif
            self?.lastMessage = kind.map { "Message “\($0)” from \(from)" } ?? "Message from \(from)"
        }
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
