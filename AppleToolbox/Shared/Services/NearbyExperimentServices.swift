import Foundation
import Combine

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
import NearbyInteraction
#endif

#if canImport(MultipeerConnectivity) && os(iOS)
import MultipeerConnectivity
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
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: "joris-nearby")
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
extension NearbyExperimentService: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        output = "Peer \(peerID.displayName): \(state.title)."
        if state == .connected, let discoveryToken = self.session?.discoveryToken {
            do {
                let archived = try NSKeyedArchiver.archivedData(withRootObject: discoveryToken, requiringSecureCoding: true)
                try session.send(archived, toPeers: [peerID], with: .reliable)
            } catch {
                output = "Could not send local Nearby token: \(error.localizedDescription)"
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
                output = "Received peer data, but it was not a valid Nearby token."
                return
            }
            let configuration = NINearbyPeerConfiguration(peerToken: token)
            self.session?.run(configuration)
            output = "Peer token received from \(peerID.displayName). Nearby ranging started."
        } catch {
            output = "Could not decode peer token: \(error.localizedDescription)"
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, transportSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        output = "Nearby advertising error: \(error.localizedDescription)"
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let transportSession else { return }
        browser.invitePeer(peerID, to: transportSession, withContext: nil, timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        output = "Peer left discovery range: \(peerID.displayName)."
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        output = "Nearby browsing error: \(error.localizedDescription)"
    }
}
#endif

#if canImport(MultipeerConnectivity) && os(iOS)
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
