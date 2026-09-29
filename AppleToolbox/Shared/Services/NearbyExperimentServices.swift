import Foundation
import Combine

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
import NearbyInteraction
#endif

#if !canImport(MultipeerConnectivity) || os(watchOS) || os(tvOS)
@MainActor
final class MultipeerConnectivityExperimentService: ObservableObject {
    @Published private(set) var output = "MultipeerConnectivity is not supported on this platform."
    @Published private(set) var isRunning = false
    @Published private(set) var connectedPeers: [String] = []
    @Published private(set) var discoveredPeers: [String] = []

    func start() { output = "MultipeerConnectivity is not supported on this platform." }
    func stop() { output = "MultipeerConnectivity is not supported on this platform." }
    func send(message: String) { output = "MultipeerConnectivity is not supported on this platform." }
}
#endif

#if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
import MultipeerConnectivity
#if canImport(UIKit)
import UIKit
#endif
#endif

#if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
/// Both peers advertise and browse. Only the peer with the smaller random identifier sends the
/// invitation, so two devices never invite each other at the same time.
nonisolated enum PeerInvitationPolicy {
    static let identifierKey = "peer"

    static func shouldInvite(localIdentifier: String, discoveryInfo: [String: String]?) -> Bool {
        guard let remoteIdentifier = discoveryInfo?[identifierKey] else { return true } // Older builds without an identifier.
        return localIdentifier < remoteIdentifier
    }
}
#endif

@MainActor
final class NearbyExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Nearby Interaction is ready."
    @Published private(set) var isRunning = false

    #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
    private var session: NISession?
    #endif

    #if canImport(MultipeerConnectivity) && os(iOS)
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    nonisolated private let invitationIdentifier = UUID().uuidString
    private var transportSession: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
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
        #if canImport(MultipeerConnectivity) && os(iOS)
        let transport = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        transport.delegate = self
        transportSession = transport
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: [PeerInvitationPolicy.identifierKey: invitationIdentifier], serviceType: "joris-nearby")
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "joris-nearby")
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        output = "Session created.\nPrecise distance: \(capabilities.supportsPreciseDistanceMeasurement)\nDirection: \(capabilities.supportsDirectionMeasurement)\nCamera assistance: \(capabilities.supportsCameraAssistance)\n\nAdvertising and browsing for a nearby Apple Toolbox peer."
        #else
        output = "Session created.\nPrecise distance: \(capabilities.supportsPreciseDistanceMeasurement)\nDirection: \(capabilities.supportsDirectionMeasurement)\nCamera assistance: \(capabilities.supportsCameraAssistance)\n\nA peer discovery token is required."
        #endif
        #else
        output = "Nearby Interaction is not supported on this platform."
        #endif
    }

    func stop() {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        session?.invalidate()
        session = nil
        #if canImport(MultipeerConnectivity) && os(iOS)
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        transportSession?.disconnect()
        advertiser = nil
        browser = nil
        transportSession = nil
        #endif
        isRunning = false
        output = "Nearby Interaction session stopped."
        #else
        output = "Nearby Interaction is not supported on this platform."
        #endif
    }
}

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
extension NearbyExperimentService: NISessionDelegate {
    func session(_ session: NISession, didGenerateShareableConfigurationData data: Data, for object: NINearbyObject) {
        output = "Nearby configuration data generated. A platform-specific peer transport is required to exchange it."
    }

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

#if canImport(MultipeerConnectivity) && os(iOS)
// MultipeerConnectivity calls these delegates on private queues; all state changes hop to the main actor.
extension NearbyExperimentService: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // MCPeerID and MCSession are immutable, thread-safe Objective-C objects that MultipeerConnectivity shares across queues.
        nonisolated(unsafe) let peerID = peerID
        nonisolated(unsafe) let session = session
        Task { @MainActor [weak self] in
            guard let self else { return }
            output = "Peer \(peerID.displayName): \(state.title)."
            guard state == .connected, let discoveryToken = self.session?.discoveryToken else { return }
            do {
                let archived = try NSKeyedArchiver.archivedData(withRootObject: discoveryToken, requiringSecureCoding: true)
                try session.send(archived, toPeers: [peerID], with: .reliable)
            } catch {
                output = "Could not send local Nearby token: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peerName = peerID.displayName
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
                    output = "Received peer data, but it was not a valid Nearby token."
                    return
                }
                self.session?.run(NINearbyPeerConfiguration(peerToken: token))
                output = "Peer token received from \(peerName). Nearby ranging started."
            } catch {
                output = "Could not decode peer token: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let invitationHandler = invitationHandler // Called once, on the main actor.
        Task { @MainActor [weak self] in invitationHandler(true, self?.transportSession) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.output = "Nearby advertising error: \(message)" }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        let invite = PeerInvitationPolicy.shouldInvite(localIdentifier: invitationIdentifier, discoveryInfo: info)
        nonisolated(unsafe) let browser = browser, peerID = peerID // Thread-safe MultipeerConnectivity objects.
        Task { @MainActor [weak self] in
            guard let self, let transportSession else { return }
            if invite {
                browser.invitePeer(peerID, to: transportSession, withContext: nil, timeout: 15)
            } else {
                output = "Found \(peerID.displayName). Waiting for its invitation…"
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerName = peerID.displayName
        Task { @MainActor [weak self] in self?.output = "Peer left discovery range: \(peerName)." }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.output = "Nearby browsing error: \(message)" }
    }
}
#endif

#if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
@MainActor
final class MultipeerConnectivityExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Ready to discover nearby Apple Toolbox peers."
    @Published private(set) var isRunning = false
    @Published private(set) var connectedPeers: [String] = []
    @Published private(set) var discoveredPeers: [String] = []

    private let peerID: MCPeerID
    nonisolated private let invitationIdentifier = UUID().uuidString
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        #if os(macOS)
        let displayName = Host.current().localizedName ?? "Mac"
        #else
        let displayName = UIDevice.current.name
        #endif
        peerID = MCPeerID(displayName: displayName)
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["app": "apple-toolbox", PeerInvitationPolicy.identifierKey: invitationIdentifier], serviceType: "apple-toolbox")
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: "apple-toolbox")
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        isRunning = true
        output = "Advertising as \(peerID.displayName) and browsing for nearby peers.\n\nStart this experiment on another Apple Toolbox device to connect."
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        isRunning = false
        connectedPeers = []
        discoveredPeers = []
        output = "MultipeerConnectivity session stopped."
    }

    func send(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            output = "Enter a message before sending."
            return
        }
        guard let session, !session.connectedPeers.isEmpty else {
            output = "No connected peer. Start the experiment on another device first."
            return
        }
        do {
            try session.send(Data(trimmed.utf8), toPeers: session.connectedPeers, with: .reliable)
            output = "Sent to \(session.connectedPeers.map(\.displayName).joined(separator: ", ")):\n\(trimmed)"
        } catch {
            output = "Could not send message: \(error.localizedDescription)"
        }
    }
}

extension MultipeerConnectivityExperimentService: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peerName = peerID.displayName
        let connected = session.connectedPeers.map(\.displayName)
        Task { @MainActor [weak self] in
            self?.connectedPeers = connected
            self?.output = "Peer \(peerName): \(state.title).\nConnected peers: \(connected.count)"
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let message = String(decoding: data, as: UTF8.self)
        let peerName = peerID.displayName
        Task { @MainActor [weak self] in self?.output = "Received from \(peerName):\n\(message)" }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let invitationHandler = invitationHandler // Called once, on the main actor.
        Task { @MainActor [weak self] in invitationHandler(true, self?.session) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.output = "Could not advertise: \(message)" }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        let invite = PeerInvitationPolicy.shouldInvite(localIdentifier: invitationIdentifier, discoveryInfo: info)
        nonisolated(unsafe) let browser = browser, peerID = peerID // Thread-safe MultipeerConnectivity objects.
        Task { @MainActor [weak self] in
            guard let self, !discoveredPeers.contains(peerID.displayName) else { return }
            discoveredPeers.append(peerID.displayName)
            guard let session else { return }
            if invite {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
                output = "Found \(peerID.displayName). Sending connection invitation…"
            } else {
                output = "Found \(peerID.displayName). Waiting for its invitation…"
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerName = peerID.displayName
        Task { @MainActor [weak self] in
            self?.discoveredPeers.removeAll { $0 == peerName }
            self?.output = "Peer left discovery: \(peerName)."
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.output = "Could not browse for peers: \(message)" }
    }
}

private extension MCSessionState {
    var title: String {
        switch self {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .notConnected: return "disconnected"
        @unknown default: return "unknown"
        }
    }
}
#endif
