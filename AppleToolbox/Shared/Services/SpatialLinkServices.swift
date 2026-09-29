import Foundation
import Combine

#if canImport(Network)
import Network
#endif
#if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
import MultipeerConnectivity
#endif
#if canImport(NearbyInteraction) && os(iOS)
import NearbyInteraction
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Wire format (pure, tested)

/// What a device tells its peers about itself.
nonisolated struct SpatialLinkDeviceInfo: Codable, Equatable, Sendable {
    let name: String
    let platform: String
    let supportsUWB: Bool
    let system: String
}

/// Messages exchanged over the Multipeer session. Round trips use the sender's own monotonic clock,
/// so the two devices' clocks never need to agree.
nonisolated struct SpatialLinkMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case hello, ping, pong }

    let kind: Kind
    /// Sender's `systemUptime` for pings; a pong echoes the ping's value.
    let sentAt: TimeInterval
    var device: SpatialLinkDeviceInfo?
    /// Archived NIDiscoveryToken of the session the sender created for this peer.
    var token: Data?
    /// Sender's network path summary, e.g. "Satisfied via Wi-Fi (en0)".
    var path: String?
}

nonisolated enum SpatialLinkCodec {
    static let serviceType = "toolbox-link"
    static let platformKey = "platform"
    static let uwbKey = "uwb"

    static func encode(_ message: SpatialLinkMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) throws -> SpatialLinkMessage {
        try JSONDecoder().decode(SpatialLinkMessage.self, from: data)
    }

    static func roundTripMilliseconds(sentAt: TimeInterval, receivedAt: TimeInterval) -> Int {
        max(0, Int(((receivedAt - sentAt) * 1000).rounded()))
    }

    #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
    /// Bonjour TXT values advertised before a connection exists.
    static func discoveryInfo(identifier: String, platform: String, supportsUWB: Bool) -> [String: String] {
        [PeerInvitationPolicy.identifierKey: identifier, platformKey: platform, uwbKey: supportsUWB ? "1" : "0"]
    }
    #endif

    static func platform(in info: [String: String]?) -> String? { info?[platformKey] }
    static func supportsUWB(in info: [String: String]?) -> Bool? { info?[uwbKey].map { $0 == "1" } }
}

/// A nearby Apple Toolbox device as the link sees it.
struct SpatialLinkPeer: Identifiable, Equatable {
    enum State: String { case discovered = "Discovered", connecting = "Connecting", connected = "Connected", disconnected = "Disconnected", lost = "Out of range" }

    let id: String
    var name: String
    var platform: String
    var state: State
    var supportsUWB: Bool?
    var isRanging = false
    var distance: Float?
    var azimuth: Float?
    var latencyMilliseconds: Int?
    var networkPath: String?
    var system: String?
    var lastSeen = Date()

    var transports: [String] {
        var transports = ["Multipeer"]
        if isRanging { transports.append("UWB") }
        return transports
    }
}

// MARK: - Service

@MainActor
final class SpatialLinkService: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var peers: [SpatialLinkPeer] = []
    @Published private(set) var localPath: NetworkPathSnapshot?
    @Published private(set) var log: [NetworkLogEntry] = []
    let localDevice: SpatialLinkDeviceInfo

    #if canImport(Network)
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "apple-toolbox.spatial-link-path")
    #endif
    private var pingTask: Task<Void, Never>?

    #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
    private let peerID: MCPeerID
    nonisolated private let invitationIdentifier = UUID().uuidString
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var remotePeers: [String: MCPeerID] = [:]
    #endif
    #if canImport(NearbyInteraction) && os(iOS)
    /// One NISession per peer; each ranges with exactly one other device.
    private var rangingSessions: [String: NISession] = [:]
    #endif

    override init() {
        let name = ContinuityExperimentService.deviceName
        localDevice = SpatialLinkDeviceInfo(name: name, platform: Self.platformName, supportsUWB: Self.localSupportsUWB,
                                            system: ProcessInfo.processInfo.operatingSystemVersionString)
        #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
        peerID = MCPeerID(displayName: name)
        #endif
        super.init()
    }

    static var platformName: String {
        switch CurrentPlatform.value {
        case .iOS: "iPhone"
        case .iPadOS: "iPad"
        case .macOS: "Mac"
        case .tvOS: "Apple TV"
        case .watchOS: "Apple Watch"
        }
    }

    static var localSupportsUWB: Bool {
        #if canImport(NearbyInteraction) && os(iOS)
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        #else
        false
        #endif
    }

    func start() {
        #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
        guard !isRunning else { return }
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        let info = SpatialLinkCodec.discoveryInfo(identifier: invitationIdentifier, platform: localDevice.platform, supportsUWB: localDevice.supportsUWB)
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info, serviceType: SpatialLinkCodec.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: SpatialLinkCodec.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        isRunning = true
        peers = []
        startPathMonitor()
        startPinging()
        append(.info, "Advertising \(localDevice.name) (\(localDevice.platform), UWB \(localDevice.supportsUWB ? "yes" : "no")) as _\(SpatialLinkCodec.serviceType)._tcp and browsing for other Apple Toolbox devices.")
        #else
        append(.error, "MultipeerConnectivity is not available on this platform.")
        #endif
    }

    func stop() {
        #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        remotePeers = [:]
        #endif
        #if canImport(NearbyInteraction) && os(iOS)
        rangingSessions.values.forEach { $0.invalidate() }
        rangingSessions = [:]
        #endif
        #if canImport(Network)
        pathMonitor?.cancel()
        pathMonitor = nil
        #endif
        pingTask?.cancel()
        pingTask = nil
        if isRunning { append(.info, "Spatial Link stopped.") }
        isRunning = false
        peers = []
    }

    // MARK: Network reachability

    private func startPathMonitor() {
        #if canImport(Network)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let snapshot = NetworkPathSnapshot(path: path)
            Task { @MainActor in self?.localPath = snapshot }
        }
        monitor.start(queue: pathQueue)
        pathMonitor = monitor
        #endif
    }

    // MARK: Latency

    private func startPinging() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pingPeers()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func pingPeers() {
        #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
        guard let session, !session.connectedPeers.isEmpty else { return }
        let ping = SpatialLinkMessage(kind: .ping, sentAt: ProcessInfo.processInfo.systemUptime, path: localPath?.summary)
        send(ping, to: session.connectedPeers)
        #endif
        #if os(iOS)
        // The paired Apple Watch is reached through WatchConnectivity, not Multipeer.
        let watch = ContinuityExperimentService.shared
        if watch.isReachable { watch.ping() }
        #endif
    }

    // MARK: Peer bookkeeping

    private func update(_ id: String, _ change: (inout SpatialLinkPeer) -> Void) {
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        change(&peers[index])
        peers[index].lastSeen = Date()
    }

    private func upsert(id: String, name: String, platform: String?, supportsUWB: Bool?, state: SpatialLinkPeer.State) {
        if peers.contains(where: { $0.id == id }) {
            update(id) {
                $0.state = state
                if let platform { $0.platform = platform }
                if let supportsUWB { $0.supportsUWB = supportsUWB }
            }
        } else {
            peers.append(SpatialLinkPeer(id: id, name: name, platform: platform ?? "Unknown", state: state, supportsUWB: supportsUWB))
            peers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func append(_ kind: NetworkLogEntry.Kind, _ text: String) {
        log = NetworkLogFormatter.appending(NetworkLogEntry(kind, text), to: log)
    }

    func clearLog() { log = [] }

    #if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
    /// MCPeerID hashes are equal for the same remote peer; display names alone may repeat (for example "iPhone").
    nonisolated private static func key(for peerID: MCPeerID) -> String { "\(peerID.displayName)#\(peerID.hash)" }

    private func send(_ message: SpatialLinkMessage, to peerIDs: [MCPeerID]) {
        guard let session, !peerIDs.isEmpty else { return }
        do {
            try session.send(SpatialLinkCodec.encode(message), toPeers: peerIDs, with: .reliable)
        } catch {
            append(.error, "send \(message.kind.rawValue) failed: \(error.localizedDescription)")
        }
    }

    private func connected(_ peerID: MCPeerID, key: String) {
        remotePeers[key] = peerID
        upsert(id: key, name: peerID.displayName, platform: nil, supportsUWB: nil, state: .connected)
        append(.state, "\(peerID.displayName) connected")
        var hello = SpatialLinkMessage(kind: .hello, sentAt: ProcessInfo.processInfo.systemUptime, device: localDevice, path: localPath?.summary)
        // Only offer a UWB token when the peer did not advertise itself as UWB-less.
        if peers.first(where: { $0.id == key })?.supportsUWB != false {
            hello.token = localRangingToken(for: key)
        }
        send(hello, to: [peerID])
    }

    private func disconnected(_ peerID: MCPeerID, key: String) {
        remotePeers[key] = nil
        stopRanging(with: key)
        update(key) {
            $0.state = .disconnected
            $0.latencyMilliseconds = nil
        }
        append(.state, "\(peerID.displayName) disconnected")
    }

    private func received(_ data: Data, from key: String, name: String) {
        let message: SpatialLinkMessage
        do {
            message = try SpatialLinkCodec.decode(data)
        } catch {
            append(.error, "Undecodable message from \(name): \(error.localizedDescription)")
            return
        }
        switch message.kind {
        case .hello:
            if let device = message.device {
                upsert(id: key, name: device.name, platform: device.platform, supportsUWB: device.supportsUWB, state: .connected)
                update(key) {
                    $0.name = device.name
                    $0.system = device.system
                }
                append(.received, "hello from \(device.name): \(device.platform), UWB \(device.supportsUWB ? "yes" : "no")")
            }
            update(key) { $0.networkPath = message.path ?? $0.networkPath }
            if let token = message.token { startRanging(with: key, tokenData: token) }
        case .ping:
            update(key) { $0.networkPath = message.path ?? $0.networkPath }
            if let peerID = remotePeers[key] {
                send(SpatialLinkMessage(kind: .pong, sentAt: message.sentAt, path: localPath?.summary), to: [peerID])
            }
        case .pong:
            let milliseconds = SpatialLinkCodec.roundTripMilliseconds(sentAt: message.sentAt, receivedAt: ProcessInfo.processInfo.systemUptime)
            update(key) {
                $0.latencyMilliseconds = milliseconds
                $0.networkPath = message.path ?? $0.networkPath
            }
        }
    }
    #endif

    // MARK: UWB ranging

    /// Creates the NISession for this peer (when this device has UWB) and returns its archived discovery token.
    private func localRangingToken(for key: String) -> Data? {
        #if canImport(NearbyInteraction) && os(iOS)
        guard localDevice.supportsUWB else { return nil }
        let session = rangingSessions[key] ?? {
            let session = NISession()
            session.delegate = self // Delegate calls arrive on the main queue.
            rangingSessions[key] = session
            return session
        }()
        guard let token = session.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        #else
        return nil
        #endif
    }

    private func startRanging(with key: String, tokenData: Data) {
        #if canImport(NearbyInteraction) && os(iOS)
        guard localDevice.supportsUWB else {
            append(.info, "The peer offers UWB, but this device has no UWB chip.")
            return
        }
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: tokenData) else {
            append(.error, "The peer's discovery token could not be decoded.")
            return
        }
        _ = localRangingToken(for: key) // Makes sure the session for this peer exists.
        rangingSessions[key]?.run(NINearbyPeerConfiguration(peerToken: token))
        update(key) { $0.isRanging = true }
        append(.state, "UWB ranging started with \(peers.first { $0.id == key }?.name ?? "peer")")
        #endif
    }

    private func stopRanging(with key: String) {
        #if canImport(NearbyInteraction) && os(iOS)
        rangingSessions.removeValue(forKey: key)?.invalidate()
        #endif
        update(key) {
            $0.isRanging = false
            $0.distance = nil
            $0.azimuth = nil
        }
    }

    #if canImport(NearbyInteraction) && os(iOS)
    private func key(for session: NISession) -> String? {
        rangingSessions.first { $0.value === session }?.key
    }
    #endif
}

#if canImport(NearbyInteraction) && os(iOS)
// NISession calls its delegate on the main queue because no delegateQueue is set.
extension SpatialLinkService: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let key = key(for: session), let object = nearbyObjects.first else { return }
        let azimuth = object.direction.map(NearbyGeometry.azimuth) ?? object.horizontalAngle
        update(key) {
            $0.distance = object.distance
            $0.azimuth = azimuth
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let key = key(for: session) else { return }
        update(key) {
            $0.distance = nil
            $0.azimuth = nil
        }
        if reason == .timeout, let configuration = session.configuration { session.run(configuration) }
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let configuration = session.configuration { session.run(configuration) }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard let key = key(for: session) else { return }
        rangingSessions[key] = nil
        update(key) {
            $0.isRanging = false
            $0.distance = nil
            $0.azimuth = nil
        }
        append(.error, "UWB session ended: \(NearbyGeometry.errorDescription(code: (error as NSError).code))")
    }
}
#endif

#if canImport(MultipeerConnectivity) && !os(watchOS) && !os(tvOS)
// MultipeerConnectivity calls these delegates on private queues; all state changes hop to the main actor.
extension SpatialLinkService: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let key = Self.key(for: peerID)
        nonisolated(unsafe) let peerID = peerID // Immutable, thread-safe MultipeerConnectivity object.
        Task { @MainActor [weak self] in
            guard let self, isRunning else { return }
            switch state {
            case .connected: connected(peerID, key: key)
            case .connecting: upsert(id: key, name: peerID.displayName, platform: nil, supportsUWB: nil, state: .connecting)
            case .notConnected: disconnected(peerID, key: key)
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let key = Self.key(for: peerID)
        let name = peerID.displayName
        Task { @MainActor [weak self] in
            guard let self, isRunning else { return }
            received(data, from: key, name: name)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        nonisolated(unsafe) let invitationHandler = invitationHandler // Called once, on the main actor.
        Task { @MainActor [weak self] in invitationHandler(self?.isRunning == true, self?.session) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.append(.error, "Could not advertise: \(message)") }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let key = Self.key(for: peerID)
        let invite = PeerInvitationPolicy.shouldInvite(localIdentifier: invitationIdentifier, discoveryInfo: info)
        let platform = SpatialLinkCodec.platform(in: info)
        let supportsUWB = SpatialLinkCodec.supportsUWB(in: info)
        nonisolated(unsafe) let browser = browser, peerID = peerID // Thread-safe MultipeerConnectivity objects.
        Task { @MainActor [weak self] in
            guard let self, isRunning, let session else { return }
            let known = peers.first { $0.id == key }
            upsert(id: key, name: peerID.displayName, platform: platform, supportsUWB: supportsUWB, state: known?.state == .connected ? .connected : .discovered)
            append(.state, "found \(peerID.displayName) (\(platform ?? "unknown platform"))")
            if invite && !session.connectedPeers.contains(peerID) {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let key = Self.key(for: peerID)
        let name = peerID.displayName
        Task { @MainActor [weak self] in
            guard let self, isRunning else { return }
            if peers.first(where: { $0.id == key })?.state != .connected {
                update(key) { $0.state = .lost }
            }
            append(.state, "\(name) left Bonjour discovery")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.append(.error, "Could not browse: \(message)") }
    }
}
#endif
