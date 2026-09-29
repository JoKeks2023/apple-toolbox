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

/// Pure geometry and naming for Nearby Interaction readings, shared by the Nearby and Spatial Link views.
nonisolated enum NearbyGeometry {
    /// Horizontal angle in radians (positive = to the right) from NI's unit direction vector, as in Apple's samples.
    static func azimuth(_ direction: SIMD3<Float>) -> Float {
        asin(max(-1, min(1, direction.x)))
    }

    /// Vertical angle in radians (positive = above); NI's z axis points out of the screen towards the user.
    static func elevation(_ direction: SIMD3<Float>) -> Float {
        atan2(direction.z, direction.y) + .pi / 2
    }

    static func degrees(_ radians: Float) -> String {
        let value = Int((radians * 180 / .pi).rounded())
        return value == 0 ? "0°" : String(format: "%+d°", value)
    }

    static func meters(_ distance: Float) -> String {
        distance < 10 ? String(format: "%.2f m", distance) : String(format: "%.1f m", distance)
    }

    /// Unit-circle position of a blip: x to the right, y negative = ahead. Distances beyond the range stay on the edge.
    static func radarPoint(distance: Float, azimuth: Float, range: Float) -> SIMD2<Float> {
        let radius = range > 0 ? min(max(distance, 0) / range, 1) : 0
        return SIMD2(sin(azimuth) * radius, -cos(azimuth) * radius)
    }

    /// The smallest "nice" radar range that shows every distance.
    static func radarRange(for distances: [Float]) -> Float {
        let farthest = distances.max() ?? 0
        return [1, 2, 5, 10, 20, 50, 100].first { $0 >= farthest * 1.1 } ?? 200
    }

    /// NIError codes (NIErrorDomain).
    static func errorDescription(code: Int) -> String {
        switch code {
        case -5889: "Unsupported platform: this device has no Ultra Wideband chip"
        case -5888: "Invalid configuration"
        case -5887: "Session failed and cannot be restarted"
        case -5886: "Resource usage timeout: the session ran in the background for too long"
        case -5885: "Too many active sessions"
        case -5884: "The user did not allow Nearby Interaction"
        case -5883: "Camera assistance is not supported or the ARSession configuration is incompatible"
        case -5882: "The accessory's Bluetooth peer is not available"
        case -5881: "The peer device does not support this configuration (for example extended distance)"
        case -5880: "Too many extended-distance sessions"
        default: "Error \(code)"
        }
    }
}

/// What a device reports through NIDeviceCapability; nil means the OS does not offer the query.
nonisolated struct NearbyCapabilitySummary: Equatable, Sendable {
    var preciseDistance = false
    var direction = false
    var cameraAssistance = false
    var extendedDistance = false
    var dlTDOA: Bool?
    var bluetoothChannelSounding: Bool?

    static var current: NearbyCapabilitySummary {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        NearbyCapabilitySummary(NISession.deviceCapabilities)
        #else
        NearbyCapabilitySummary()
        #endif
    }
}

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
nonisolated extension NearbyCapabilitySummary {
    init(_ capability: any NIDeviceCapability) {
        preciseDistance = capability.supportsPreciseDistanceMeasurement
        direction = capability.supportsDirectionMeasurement
        cameraAssistance = capability.supportsCameraAssistance
        extendedDistance = capability.supportsExtendedDistanceMeasurement
        #if os(iOS)
        dlTDOA = capability.supportsDLTDOAMeasurement
        if #available(iOS 27.0, *) { bluetoothChannelSounding = capability.supportsBluetoothChannelSounding }
        #endif
    }
}
#endif

/// One distance/direction update for the peer.
nonisolated struct NearbyReading: Equatable, Sendable {
    let distance: Float?
    let direction: SIMD3<Float>?
    let horizontalAngle: Float?
    let verticalEstimate: String
    let date: Date

    /// Direction when available, otherwise the camera-assisted horizontal angle.
    var azimuth: Float? { direction.map(NearbyGeometry.azimuth) ?? horizontalAngle }
}

@MainActor
final class NearbyExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Nearby Interaction is ready."
    @Published private(set) var isRunning = false
    @Published private(set) var phase = "Idle"
    @Published private(set) var peerName: String?
    @Published private(set) var reading: NearbyReading?
    @Published private(set) var convergence = "—"
    @Published private(set) var capabilities = NearbyCapabilitySummary.current
    @Published private(set) var peerCapabilities: NearbyCapabilitySummary?
    @Published private(set) var useCameraAssistance = false
    @Published private(set) var useExtendedDistance = false
    @Published private(set) var accessoryReport: String?

    #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
    private var session: NISession?
    private var peerToken: NIDiscoveryToken?
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
        capabilities = .current
        guard capabilities.preciseDistance else {
            output = "Nearby Interaction is present, but this device has no Ultra Wideband chip, so precise distance measurement is not supported."
            return
        }
        let session = NISession()
        session.delegate = self // Delegate calls arrive on the main queue (no delegateQueue set).
        self.session = session
        isRunning = true
        phase = "Waiting for a peer"
        reading = nil
        convergence = "—"
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
        output = "NISession created. Advertising and browsing for a nearby Apple Toolbox peer to exchange discovery tokens over MultipeerConnectivity."
        #else
        output = "NISession created. A peer discovery token is required; this platform has no peer transport in Apple Toolbox."
        #endif
        #else
        output = "Nearby Interaction is not supported on this platform."
        #endif
    }

    func stop() {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        session?.invalidate()
        session = nil
        peerToken = nil
        #if canImport(MultipeerConnectivity) && os(iOS)
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        transportSession?.disconnect()
        advertiser = nil
        browser = nil
        transportSession = nil
        #endif
        isRunning = false
        phase = "Idle"
        peerName = nil
        peerCapabilities = nil
        output = "Nearby Interaction session stopped."
        #else
        output = "Nearby Interaction is not supported on this platform."
        #endif
    }

    /// Camera assistance fuses UWB with ARKit for a horizontal angle and world transform on devices that support it.
    func setCameraAssistance(_ enabled: Bool) {
        useCameraAssistance = enabled
        rerunIfRanging()
    }

    /// Extended distance needs both devices to report support in NIDeviceCapability.
    func setExtendedDistance(_ enabled: Bool) {
        useExtendedDistance = enabled
        rerunIfRanging()
    }

    /// Third-party UWB accessories hand their configuration data to the app over their own Bluetooth protocol.
    /// Without an accessory there is no such data; the real initializer shows how the framework rejects it.
    func tryAccessoryConfiguration() {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        do {
            _ = try NINearbyAccessoryConfiguration(data: Data())
            accessoryReport = "NINearbyAccessoryConfiguration accepted empty data."
        } catch {
            let nsError = error as NSError
            accessoryReport = "NINearbyAccessoryConfiguration(data:) rejected the call: \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
        #else
        accessoryReport = "Nearby Interaction accessory sessions are not available on this platform."
        #endif
    }

    private func rerunIfRanging() {
        #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
        guard session != nil, peerToken != nil else { return }
        runRanging()
        #endif
    }

    #if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)

    private func runRanging() {
        guard let session, let peerToken else { return }
        let configuration = NINearbyPeerConfiguration(peerToken: peerToken)
        var notes: [String] = []
        #if os(iOS)
        if useCameraAssistance {
            if capabilities.cameraAssistance {
                configuration.isCameraAssistanceEnabled = true
                notes.append("camera assistance on (keep the camera unobstructed and move the phone slowly)")
            } else {
                notes.append("camera assistance is not supported on this device")
            }
        }
        #endif
        if useExtendedDistance {
            if capabilities.extendedDistance && peerCapabilities?.extendedDistance == true {
                configuration.isExtendedDistanceMeasurementEnabled = true
                notes.append("extended distance on")
            } else {
                notes.append("extended distance needs support on both devices (this device: \(capabilities.extendedDistance ? "yes" : "no"), peer: \(peerCapabilities.map { $0.extendedDistance ? "yes" : "no" } ?? "unknown"))")
            }
        }
        session.run(configuration)
        phase = "Ranging"
        output = "Ranging with \(peerName ?? "peer")." + (notes.isEmpty ? "" : "\n" + notes.joined(separator: "\n"))
    }

    private func receivedToken(_ token: NIDiscoveryToken, from name: String) {
        peerToken = token
        peerName = name
        peerCapabilities = NearbyCapabilitySummary(token.deviceCapabilities)
        runRanging()
    }

    private static func title(_ estimate: NINearbyObject.VerticalDirectionEstimate) -> String {
        switch estimate {
        case .same: "Same level"
        case .above: "Above"
        case .below: "Below"
        case .aboveOrBelow: "Above or below"
        case .unknown: "Unknown"
        @unknown default: "Unknown"
        }
    }
    #endif
}

#if canImport(NearbyInteraction) && !os(macOS) && !os(tvOS)
// NISession calls its delegate on the main queue because no delegateQueue is set.
extension NearbyExperimentService: NISessionDelegate {
    func session(_ session: NISession, didGenerateShareableConfigurationData data: Data, for object: NINearbyObject) {
        output = "Shareable configuration data generated (\(data.count) bytes). Only accessory sessions use it."
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        let horizontalAngle: Float? = object.horizontalAngle
        reading = NearbyReading(distance: object.distance, direction: object.direction, horizontalAngle: horizontalAngle,
                                verticalEstimate: Self.title(object.verticalDirectionEstimate), date: Date())
        phase = "Ranging"
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        switch reason {
        case .peerEnded:
            phase = "Peer ended the session"
            output = "\(peerName ?? "The peer") ended its Nearby Interaction session."
            peerToken = nil
            reading = nil
        case .timeout:
            phase = "Peer out of range"
            output = "No UWB measurements for a while (out of range or blocked). Ranging restarts automatically."
            runRanging()
        @unknown default:
            output = "Nearby object removed."
        }
    }

    func session(_ session: NISession, didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence, for object: NINearbyObject?) {
        switch convergence.status {
        case .converged:
            self.convergence = "Converged"
        case .notConverged(let reasons):
            let text = reasons.map { $0.localizedDescription ?? $0.rawValue }.joined(separator: ", ")
            self.convergence = "Not converged" + (text.isEmpty ? "" : ": \(text)")
        case .unknown:
            self.convergence = "Unknown"
        @unknown default:
            self.convergence = "Unknown"
        }
    }

    func sessionDidStartRunning(_ session: NISession) {
        phase = "Running"
    }

    func sessionWasSuspended(_ session: NISession) {
        phase = "Suspended"
        output = "Nearby Interaction session suspended (app in the background or another session took over)."
    }

    func sessionSuspensionEnded(_ session: NISession) {
        output = "Suspension ended; running the configuration again."
        runRanging()
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        let nsError = error as NSError
        isRunning = false
        phase = "Invalidated"
        output = "Nearby Interaction error \(nsError.code): \(NearbyGeometry.errorDescription(code: nsError.code)). \(nsError.localizedDescription)"
        self.session = nil
        peerToken = nil
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
            if state == .connected { phase = "Connected to \(peerID.displayName)" }
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
                receivedToken(token, from: peerName)
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
