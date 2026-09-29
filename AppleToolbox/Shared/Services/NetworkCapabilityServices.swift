import Foundation
import Combine

#if canImport(Network) && !os(watchOS)
import Network
#endif
#if canImport(NetworkExtension) && (os(iOS) || os(macOS))
import NetworkExtension
#endif
#if canImport(CoreLocation) && (os(iOS) || os(macOS))
import CoreLocation
#endif
#if canImport(CoreWLAN) && os(macOS)
import CoreWLAN
#endif

extension ExperimentAvailability {
    /// Status of the current-Wi-Fi part: iOS needs the Access Wi-Fi Information entitlement and precise location;
    /// macOS (CoreWLAN) needs location authorization. Never prompts.
    static func wifiInformation() -> ExperimentStatus {
        #if os(iOS)
        switch IdentityEntitlements.state(ofCapability: "access-wifi-information") {
        case .notProvisioned, .notDeclared: return .entitlementRequired
        default: break
        }
        return WiFiLocationRequirement.current.status
        #elseif os(macOS)
        return WiFiLocationRequirement.current.status
        #else
        return .platformUnsupported
        #endif
    }
}

/// Location state that decides whether the system reveals SSID and BSSID.
nonisolated enum WiFiLocationRequirement: Equatable {
    case notDetermined, denied, reducedAccuracy, precise, unavailable

    var status: ExperimentStatus {
        switch self {
        case .notDetermined, .reducedAccuracy: .permissionRequired
        case .denied: .permissionDenied
        case .precise: .available
        case .unavailable: .platformUnsupported
        }
    }

    var title: String {
        switch self {
        case .notDetermined: "Not requested yet"
        case .denied: "Denied or restricted"
        case .reducedAccuracy: "Allowed, but Precise Location is off"
        case .precise: "Allowed with Precise Location"
        case .unavailable: "Not available"
        }
    }

    static var current: WiFiLocationRequirement {
        #if canImport(CoreLocation) && (os(iOS) || os(macOS))
        let manager = PermissionProbe.locationManager
        return from(manager.authorizationStatus, manager.accuracyAuthorization)
        #else
        return .unavailable
        #endif
    }

    #if canImport(CoreLocation) && (os(iOS) || os(macOS))
    static func from(_ status: CLAuthorizationStatus, _ accuracy: CLAccuracyAuthorization) -> WiFiLocationRequirement {
        switch status {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: accuracy == .fullAccuracy ? .precise : .reducedAccuracy
        }
    }
    #endif
}

#if !os(watchOS)
// MARK: - Pure helpers (tested)

/// Security choices for a hotspot configuration the user enters.
nonisolated enum HotspotSecurity: String, CaseIterable, Identifiable, Sendable {
    case open, personal, wep

    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Open"
        case .personal: "WPA/WPA2/WPA3 Personal"
        case .wep: "WEP"
        }
    }
    var needsPassphrase: Bool { self != .open }
}

nonisolated enum HotspotInputValidator {
    /// A message describing the first problem, or nil when NEHotspotConfiguration accepts the values.
    static func problem(ssid: String, passphrase: String, security: HotspotSecurity) -> String? {
        let ssidBytes = ssid.utf8.count
        guard ssidBytes > 0 else { return "Enter the network name (SSID)." }
        guard ssidBytes <= 32 else { return "An SSID is at most 32 bytes; this one has \(ssidBytes)." }
        switch security {
        case .open:
            return nil
        case .personal:
            let isHexKey = passphrase.count == 64 && passphrase.allSatisfy(\.isHexDigit)
            return (8...63).contains(passphrase.count) || isHexKey ? nil : "A WPA passphrase has 8–63 characters (or 64 hex digits)."
        case .wep:
            let hex = passphrase.allSatisfy(\.isHexDigit)
            return [5, 13].contains(passphrase.count) || (hex && [10, 26].contains(passphrase.count)) ? nil : "A WEP key has 5 or 13 characters, or 10 or 26 hex digits."
        }
    }
}

nonisolated enum WiFiDescriptions {
    /// NEHotspotConfigurationError codes (NetworkExtension, NEHotspotConfigurationErrorDomain).
    static func hotspotError(code: Int) -> String {
        switch code {
        case 0: "Invalid configuration"
        case 1: "Invalid SSID"
        case 2: "Invalid WPA passphrase"
        case 3: "Invalid WEP passphrase"
        case 4: "Invalid EAP settings"
        case 5: "Invalid Hotspot 2.0 settings"
        case 6: "Invalid Hotspot 2.0 domain name"
        case 7: "The user declined to add the network"
        case 8: "Internal error (also reported when the Hotspot entitlement is missing)"
        case 9: "A previous request of this app is still pending"
        case 10: "The network is managed by a system configuration (MDM or carrier) and cannot be changed"
        case 11: "Unknown error"
        case 12: "Join once is not supported for EAP networks"
        case 13: "Already associated with this network"
        case 14: "The app is not in the foreground"
        case 15: "Invalid SSID prefix"
        case 16: "The user did not authorize the accessory"
        case 17: "The system denied configuring the accessory network"
        default: "Error \(code)"
        }
    }

    /// NEHotspotNetworkSecurityType raw values.
    static func hotspotSecurity(rawValue: Int) -> String {
        switch rawValue {
        case 0: "Open"
        case 1: "WEP"
        case 2: "WPA/WPA2/WPA3 Personal"
        case 3: "WPA/WPA2/WPA3 Enterprise"
        default: "Unknown"
        }
    }

    /// CWSecurity raw values (CoreWLAN, macOS).
    static func coreWLANSecurity(rawValue: Int) -> String {
        switch rawValue {
        case 0: "Open"
        case 1: "WEP"
        case 2: "WPA Personal"
        case 3: "WPA/WPA2 Personal"
        case 4: "WPA2 Personal"
        case 5: "Personal"
        case 6: "Dynamic WEP"
        case 7: "WPA Enterprise"
        case 8: "WPA/WPA2 Enterprise"
        case 9: "WPA2 Enterprise"
        case 10: "Enterprise"
        case 11: "WPA3 Personal"
        case 12: "WPA3 Enterprise"
        case 13: "WPA2/WPA3 Personal (transition)"
        case 14: "Enhanced Open (OWE)"
        case 15: "Enhanced Open transition"
        default: "Unknown"
        }
    }

    /// NEVPNStatus raw values.
    static func vpnStatus(rawValue: Int) -> String {
        switch rawValue {
        case 0: "Invalid (no saved configuration)"
        case 1: "Disconnected"
        case 2: "Connecting"
        case 3: "Connected"
        case 4: "Reasserting"
        case 5: "Disconnecting"
        default: "Unknown"
        }
    }
}

/// Decides the local network probe result from what the listener and browser reported.
nonisolated enum LocalNetworkProbeOutcome: String, Equatable, Sendable {
    case idle, running, granted, denied, noAnswer

    var title: String {
        switch self {
        case .idle: "Not probed"
        case .running: "Probing…"
        case .granted: "Allowed"
        case .denied: "Denied"
        case .noAnswer: "No answer"
        }
    }

    static func decide(sawOwnService: Bool, sawPolicyDenied: Bool, timedOut: Bool) -> LocalNetworkProbeOutcome {
        if sawPolicyDenied { return .denied }
        if sawOwnService { return .granted }
        return timedOut ? .noAnswer : .running
    }
}

/// One capability with its signing state, what the app can try, and the honest boundary.
struct NetworkCapabilityBoundary: Identifiable {
    enum Probe { case multicast, personalVPN, tunnelProviders, multipath }

    let id: String
    let name: String
    let gate: String
    let entitlement: String
    let isProvisioned: Bool?
    let requirement: String
    let boundary: String
    let probe: Probe?
    let probeTitle: String?
}

// MARK: - Service

@MainActor
final class WiFiCapabilityService: NSObject, ObservableObject {
    @Published private(set) var location = WiFiLocationRequirement.current
    @Published private(set) var currentNetwork: [NetworkDetailRow] = []
    @Published private(set) var wifiMessage = "Read the current network to see what the system reveals to this app."
    @Published private(set) var configuredSSIDs: [String] = []
    @Published private(set) var hotspotMessage = "Enter a network. iOS asks for confirmation before it saves or joins it."
    @Published private(set) var isApplyingHotspot = false
    @Published private(set) var probeOutcome = LocalNetworkProbeOutcome.idle
    @Published private(set) var probeLog: [NetworkLogEntry] = []
    @Published private(set) var boundaries: [NetworkCapabilityBoundary] = []
    @Published private(set) var probeResults: [String: String] = [:]
    @Published private(set) var runningProbe: NetworkCapabilityBoundary.Probe?

    #if canImport(CoreLocation) && (os(iOS) || os(macOS))
    private let locationManager = CLLocationManager()
    #endif
    #if canImport(Network) && !os(watchOS)
    private let queue = DispatchQueue(label: "apple-toolbox.wifi-capabilities")
    private var probeListener: NWListener?
    private var probeBrowser: NWBrowser?
    private var probeTimeout: Task<Void, Never>?
    private var probeGeneration = 0
    private var probeName = ""
    private var multicastGroup: NWConnectionGroup?
    private var multipathConnection: NWConnection?
    private var capabilityProbeTimeout: Task<Void, Never>?
    #endif

    override init() {
        super.init()
        #if canImport(CoreLocation) && (os(iOS) || os(macOS))
        locationManager.delegate = self
        #endif
        boundaries = Self.makeBoundaries()
    }

    var isActive: Bool { probeOutcome == .running || runningProbe != nil }

    func stop() {
        #if canImport(Network) && !os(watchOS)
        if probeOutcome == .running { finishProbe(.idle, note: "Probe stopped.") }
        finishCapabilityProbe(result: nil)
        #endif
    }

    // MARK: Location

    func requestLocationAccess() {
        #if canImport(CoreLocation) && (os(iOS) || os(macOS))
        switch location {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .reducedAccuracy:
            locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WiFiInformation") { @Sendable [weak self] error in
                let message = error?.localizedDescription
                Task { @MainActor in
                    self?.updateLocation()
                    if let message { self?.wifiMessage = "Precise location request failed: \(message)" }
                }
            }
        default:
            wifiMessage = "Location is \(location.title.lowercased()). Change it in Settings › Privacy & Security › Location Services › Apple Toolbox."
        }
        #endif
    }

    private func updateLocation() {
        location = WiFiLocationRequirement.current
        PermissionCenter.shared.invalidate()
    }

    // MARK: Current Wi-Fi

    func readCurrentNetwork() {
        location = WiFiLocationRequirement.current
        #if os(iOS)
        wifiMessage = "Calling NEHotspotNetwork.fetchCurrent…"
        NEHotspotNetwork.fetchCurrent { @Sendable [weak self] network in
            // Copied on the delivering queue; NEHotspotNetwork itself is not Sendable.
            let rows = network.map { network in [
                NetworkDetailRow(title: "SSID", value: network.ssid),
                NetworkDetailRow(title: "BSSID", value: network.bssid),
                NetworkDetailRow(title: "Security", value: WiFiDescriptions.hotspotSecurity(rawValue: network.securityType.rawValue)),
            ] }
            Task { @MainActor in self?.applyCurrentNetwork(rows) }
        }
        #elseif os(macOS)
        applyCoreWLAN()
        #else
        wifiMessage = "This platform has no public API for the current Wi-Fi network."
        #endif
    }

    #if os(iOS)
    private func applyCurrentNetwork(_ rows: [NetworkDetailRow]?) {
        if let rows {
            currentNetwork = rows
            wifiMessage = "NEHotspotNetwork.fetchCurrent returned the current network."
            return
        }
        currentNetwork = []
        let entitlement = IdentityEntitlements.state(ofCapability: "access-wifi-information")
        var reasons = ["NEHotspotNetwork.fetchCurrent returned nil. The system only answers when all of these hold:"]
        reasons.append("• Entitlement: " + IdentityEntitlements.summary(of: entitlement, key: "com.apple.developer.networking.wifi-info"))
        reasons.append("• Location: \(location.title). Precise location is required unless this app configured the network itself or has an active VPN or DNS settings configuration.")
        reasons.append("• The device must be connected to a Wi-Fi network (the Simulator never is).")
        wifiMessage = reasons.joined(separator: "\n")
    }
    #endif

    #if os(macOS)
    private func applyCoreWLAN() {
        guard let interface = CWWiFiClient.shared().interface() else {
            currentNetwork = []
            wifiMessage = "CoreWLAN reports no Wi-Fi interface on this Mac."
            return
        }
        var rows = [NetworkDetailRow(title: "Interface", value: interface.interfaceName ?? "—"),
                    NetworkDetailRow(title: "Wi-Fi power", value: interface.powerOn() ? "On" : "Off")]
        let ssid = interface.ssid()
        rows.append(NetworkDetailRow(title: "SSID", value: ssid ?? "Hidden (needs location authorization)"))
        rows.append(NetworkDetailRow(title: "BSSID", value: interface.bssid() ?? "Hidden (needs location authorization)"))
        if interface.powerOn() {
            rows.append(NetworkDetailRow(title: "Security", value: WiFiDescriptions.coreWLANSecurity(rawValue: interface.security().rawValue)))
            rows.append(NetworkDetailRow(title: "RSSI · noise", value: "\(interface.rssiValue()) dBm · \(interface.noiseMeasurement()) dBm"))
            rows.append(NetworkDetailRow(title: "Transmit rate", value: String(format: "%.0f Mbit/s", interface.transmitRate())))
            if let channel = interface.wlanChannel() {
                let band = switch channel.channelBand { case .band2GHz: "2.4 GHz"; case .band5GHz: "5 GHz"; case .band6GHz: "6 GHz"; default: "unknown band" }
                rows.append(NetworkDetailRow(title: "Channel", value: "\(channel.channelNumber) · \(band)"))
            }
            if let country = interface.countryCode() { rows.append(NetworkDetailRow(title: "Country code", value: country)) }
        }
        currentNetwork = rows
        wifiMessage = ssid == nil && interface.powerOn()
            ? "CoreWLAN answered, but macOS hides SSID and BSSID until the app has location authorization (\(location.title.lowercased()))."
            : "CoreWLAN (CWWiFiClient) returned the current interface state."
    }
    #endif

    // MARK: Hotspot

    func showHotspotProblem(_ problem: String) {
        hotspotMessage = problem
    }

    func refreshConfiguredNetworks() {
        #if os(iOS)
        NEHotspotConfigurationManager.shared.getConfiguredSSIDs { @Sendable [weak self] ssids in
            Task { @MainActor in self?.configuredSSIDs = ssids.sorted() }
        }
        #endif
    }

    func joinHotspot(ssid rawSSID: String, passphrase: String, security: HotspotSecurity, joinOnce: Bool) {
        #if os(iOS)
        let ssid = rawSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = HotspotInputValidator.problem(ssid: ssid, passphrase: passphrase, security: security) {
            hotspotMessage = problem
            return
        }
        let configuration = switch security {
        case .open: NEHotspotConfiguration(ssid: ssid)
        case .personal: NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        case .wep: NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: true)
        }
        configuration.joinOnce = joinOnce
        isApplyingHotspot = true
        hotspotMessage = "Asking iOS to add and join “\(ssid)”…"
        NEHotspotConfigurationManager.shared.apply(configuration) { @Sendable [weak self] error in
            let nsError = error.map { $0 as NSError }
            let report = nsError.map { "\($0.domain) \($0.code): \(WiFiDescriptions.hotspotError(code: $0.code)). \($0.localizedDescription)" }
            let alreadyJoined = nsError?.domain == NEHotspotConfigurationErrorDomain && nsError?.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
            Task { @MainActor in
                guard let self else { return }
                self.isApplyingHotspot = false
                if let report, !alreadyJoined {
                    self.hotspotMessage = "apply failed: \(report)"
                } else {
                    self.hotspotMessage = alreadyJoined ? "Already connected to “\(ssid)”." : "iOS saved “\(ssid)” and joins it when it is in range\(joinOnce ? " (join once: removed when the app goes to the background)" : "")."
                }
                self.refreshConfiguredNetworks()
                self.readCurrentNetwork()
            }
        }
        #else
        hotspotMessage = "NEHotspotConfigurationManager is only available on iPhone and iPad."
        #endif
    }

    func removeHotspot(_ ssid: String) {
        #if os(iOS)
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
        hotspotMessage = "Removed the configuration for “\(ssid)”."
        refreshConfiguredNetworks()
        #endif
    }

    // MARK: Local network probe

    /// Advertises a uniquely named Bonjour service and browses for it: seeing it proves local network access,
    /// PolicyDenied proves a denial. There is no API that reads the permission directly.
    func runLocalNetworkProbe() {
        #if canImport(Network) && !os(watchOS)
        finishProbe(.idle, note: nil)
        probeLog = []
        probeGeneration += 1
        let generation = probeGeneration
        probeName = "probe-" + UUID().uuidString.prefix(8).lowercased()
        let type = BonjourServiceType.echo.type
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: probeName, type: type)
            listener.stateUpdateHandler = { @Sendable [weak self] state in
                Task { @MainActor in self?.probeListenerChanged(state, generation: generation) }
            }
            listener.newConnectionHandler = { @Sendable connection in connection.cancel() }
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: parameters)
            browser.stateUpdateHandler = { @Sendable [weak self] state in
                Task { @MainActor in self?.probeBrowserChanged(state, generation: generation) }
            }
            browser.browseResultsChangedHandler = { @Sendable [weak self] results, _ in
                let names = results.compactMap { result -> String? in
                    if case .service(let name, _, _, _) = result.endpoint { return name }
                    return nil
                }
                Task { @MainActor in self?.probeFound(names, generation: generation) }
            }
            probeListener = listener
            probeBrowser = browser
            probeOutcome = .running
            appendProbe(.info, "Advertising \(probeName).\(type) and browsing for it…")
            listener.start(queue: queue)
            browser.start(queue: queue)
            probeTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.probeTimedOut(generation: generation)
            }
        } catch {
            appendProbe(.error, "NWListener could not be created: \(error.localizedDescription)")
        }
        #endif
    }

    #if canImport(Network) && !os(watchOS)
    private func probeListenerChanged(_ state: NWListener.State, generation: Int) {
        guard generation == probeGeneration else { return }
        switch state {
        case .ready: appendProbe(.state, "listener ready")
        case .waiting(let error), .failed(let error):
            appendProbe(.error, "listener: \(NetworkErrorExplainer.explain(error))")
            if NetworkErrorExplainer.isLocalNetworkDenial(error) { decideProbe(sawOwnService: false, sawPolicyDenied: true) }
        default: break
        }
    }

    private func probeBrowserChanged(_ state: NWBrowser.State, generation: Int) {
        guard generation == probeGeneration else { return }
        switch state {
        case .ready: appendProbe(.state, "browser ready")
        case .waiting(let error), .failed(let error):
            appendProbe(.error, "browser: \(NetworkErrorExplainer.explain(error))")
            if NetworkErrorExplainer.isLocalNetworkDenial(error) { decideProbe(sawOwnService: false, sawPolicyDenied: true) }
        default: break
        }
    }

    private func probeFound(_ names: [String], generation: Int) {
        guard generation == probeGeneration else { return }
        appendProbe(.received, "browser sees \(names.count) service\(names.count == 1 ? "" : "s")")
        decideProbe(sawOwnService: names.contains(probeName), sawPolicyDenied: false)
    }

    private func probeTimedOut(generation: Int) {
        guard generation == probeGeneration, probeOutcome == .running else { return }
        decideProbe(sawOwnService: false, sawPolicyDenied: false, timedOut: true)
    }

    private func decideProbe(sawOwnService: Bool, sawPolicyDenied: Bool, timedOut: Bool = false) {
        let outcome = LocalNetworkProbeOutcome.decide(sawOwnService: sawOwnService, sawPolicyDenied: sawPolicyDenied, timedOut: timedOut)
        guard outcome != .running else { return }
        let note = switch outcome {
        case .granted: "The browser found this device's own probe service, so local network access is allowed."
        case .denied: "Bonjour returned PolicyDenied: local network access is denied. Allow it in Settings › Privacy & Security › Local Network."
        default: "No result within 12 s. The permission alert may still be waiting for an answer, or no local network is available. Run the probe again afterwards."
        }
        finishProbe(outcome, note: note)
    }

    private func finishProbe(_ outcome: LocalNetworkProbeOutcome, note: String?) {
        probeGeneration += 1
        probeTimeout?.cancel()
        probeTimeout = nil
        probeListener?.stateUpdateHandler = nil
        probeListener?.cancel()
        probeListener = nil
        probeBrowser?.stateUpdateHandler = nil
        probeBrowser?.browseResultsChangedHandler = nil
        probeBrowser?.cancel()
        probeBrowser = nil
        if probeOutcome == .running || outcome != .idle { probeOutcome = outcome }
        if let note { appendProbe(outcome == .denied ? .error : .state, note) }
        PermissionCenter.shared.invalidate()
    }
    #endif

    private func appendProbe(_ kind: NetworkLogEntry.Kind, _ text: String) {
        probeLog = NetworkLogFormatter.appending(NetworkLogEntry(kind, text), to: probeLog)
    }

    // MARK: Capability boundaries

    func refreshBoundaries() {
        boundaries = Self.makeBoundaries()
    }

    func runProbe(_ probe: NetworkCapabilityBoundary.Probe, id: String) {
        #if canImport(Network) && !os(watchOS)
        finishCapabilityProbe(result: nil)
        runningProbe = probe
        probeResults[id] = "Running…"
        switch probe {
        case .multicast: startMulticastProbe(id: id)
        case .personalVPN: loadPersonalVPN(id: id)
        case .tunnelProviders: loadTunnelProviders(id: id)
        case .multipath: startMultipathProbe(id: id)
        }
        #endif
    }

    #if canImport(Network) && !os(watchOS)
    /// Joining a multicast group needs the Multicast Networking entitlement on iOS and iPadOS.
    private func startMulticastProbe(id: String) {
        do {
            let group = try NWMulticastGroup(for: [.hostPort(host: "239.255.77.77", port: 47777)])
            let connectionGroup = NWConnectionGroup(with: group, using: .udp)
            connectionGroup.stateUpdateHandler = { @Sendable [weak self] state in
                let text: String? = switch state {
                case .ready: "NWConnectionGroup is ready: this app may send and receive on 239.255.77.77:47777."
                case .waiting(let error): "waiting: \(NetworkErrorExplainer.explain(error))"
                case .failed(let error): "failed: \(NetworkErrorExplainer.explain(error))"
                default: nil
                }
                guard let text else { return }
                Task { @MainActor in self?.capabilityProbeFinished(id: id, result: text) }
            }
            connectionGroup.setReceiveHandler { @Sendable _, _, _ in }
            multicastGroup = connectionGroup
            connectionGroup.start(queue: queue)
            scheduleCapabilityTimeout(id: id)
        } catch {
            capabilityProbeFinished(id: id, result: "NWMulticastGroup could not be created: \(error.localizedDescription)")
        }
    }

    private func startMultipathProbe(id: String) {
        let parameters = NWParameters.tls
        parameters.multipathServiceType = .handover
        let connection = NWConnection(host: "www.apple.com", port: 443, using: parameters)
        connection.stateUpdateHandler = { @Sendable [weak self] state in
            let text: String? = switch state {
            case .ready: "A handover-mode connection to www.apple.com:443 is ready. Whether Multipath TCP was negotiated is not exposed; the server must support it and the entitlement must be provisioned."
            case .waiting(let error): "waiting: \(NetworkErrorExplainer.explain(error))"
            case .failed(let error): "failed: \(NetworkErrorExplainer.explain(error))"
            default: nil
            }
            guard let text else { return }
            Task { @MainActor in self?.capabilityProbeFinished(id: id, result: text) }
        }
        multipathConnection = connection
        connection.start(queue: queue)
        scheduleCapabilityTimeout(id: id)
    }

    private func scheduleCapabilityTimeout(id: String) {
        capabilityProbeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.capabilityProbeFinished(id: id, result: "No state change within 10 s.")
        }
    }

    private func capabilityProbeFinished(id: String, result: String) {
        guard runningProbe != nil else { return }
        probeResults[id] = result
        finishCapabilityProbe(result: result)
    }

    private func finishCapabilityProbe(result: String?) {
        capabilityProbeTimeout?.cancel()
        capabilityProbeTimeout = nil
        multicastGroup?.stateUpdateHandler = nil
        multicastGroup?.cancel()
        multicastGroup = nil
        multipathConnection?.stateUpdateHandler = nil
        multipathConnection?.cancel()
        multipathConnection = nil
        runningProbe = nil
    }
    #endif

    private func loadPersonalVPN(id: String) {
        #if canImport(NetworkExtension) && (os(iOS) || os(macOS))
        NEVPNManager.shared().loadFromPreferences { @Sendable [weak self] error in
            let message = error.map { error in
                let nsError = error as NSError
                return "loadFromPreferences failed: \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
            }
            Task { @MainActor in
                guard let self else { return }
                if let message {
                    self.capabilityProbeFinished(id: id, result: message)
                    return
                }
                let manager = NEVPNManager.shared()
                let saved = manager.protocolConfiguration != nil
                self.capabilityProbeFinished(id: id, result: saved
                    ? "Saved configuration “\(manager.localizedDescription ?? "Unnamed")” · enabled: \(manager.isEnabled ? "yes" : "no") · status: \(WiFiDescriptions.vpnStatus(rawValue: manager.connection.status.rawValue))"
                    : "loadFromPreferences succeeded: this app has not saved a Personal VPN configuration. Apple Toolbox does not create one; saving would ask the user to allow a VPN configuration.")
            }
        }
        #else
        capabilityProbeFinished(id: id, result: "NEVPNManager is not available on this platform.")
        #endif
    }

    private func loadTunnelProviders(id: String) {
        #if canImport(NetworkExtension) && (os(iOS) || os(macOS))
        NETunnelProviderManager.loadAllFromPreferences { @Sendable [weak self] managers, error in
            let result: String
            if let error {
                let nsError = error as NSError
                result = "loadAllFromPreferences failed: \(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
            } else if let managers, !managers.isEmpty {
                result = "\(managers.count) tunnel configuration(s): " + managers.map { $0.localizedDescription ?? "Unnamed" }.joined(separator: ", ")
            } else {
                result = "No tunnel provider configurations. The Mac app ships no Network Extension; Apple Toolbox's packet tunnel provider is part of the iOS app."
            }
            Task { @MainActor in self?.capabilityProbeFinished(id: id, result: result) }
        }
        #else
        capabilityProbeFinished(id: id, result: "NETunnelProviderManager is not available on this platform.")
        #endif
    }

    /// Multipath is an iOS/iPadOS capability; tvOS has none of these configuration APIs. On iOS, Personal VPN and the
    /// packet tunnel have their own sections with the full configuration flow instead of a read-only probe.
    private static func isProbeSupported(_ probe: NetworkCapabilityBoundary.Probe) -> Bool {
        #if os(iOS)
        return probe == .multicast || probe == .multipath
        #elseif os(macOS)
        return probe != .multipath
        #else
        return false
        #endif
    }

    private static var personalVPNBoundary: String {
        #if os(iOS)
        "NEVPNManager configures the built-in IKEv2/IPsec client. The Personal VPN section below saves a configuration from the form (iOS asks once) and connects; without a real IKEv2 server the attempt fails and the system's disconnect error is shown."
        #else
        "NEVPNManager configures the built-in IKEv2/IPsec client. On the Mac the experiment only reads the preferences; the configuration flow is part of the iOS app."
        #endif
    }

    private static var networkExtensionBoundary: String {
        #if os(iOS)
        "Apple Toolbox ships a packet tunnel provider (AppleToolbox Packet Tunnel, packet-tunnel-provider). The Packet tunnel section below installs its configuration, starts it and reads its counters. App proxies, content filters and DNS proxies would each need their own extension."
        #else
        "Packet tunnels, app proxies, content filters and DNS proxies run in separate Network Extension targets. Apple Toolbox's packet tunnel ships only in the iOS app, so here it can only list configurations."
        #endif
    }

    private static func makeBoundaries() -> [NetworkCapabilityBoundary] {
        let rows: [(id: String, probe: NetworkCapabilityBoundary.Probe?, probeTitle: String?, boundary: String)] = [
            ("multicast-networking", .multicast, "Join a multicast group",
             "Sending or receiving multicast and broadcast (NWConnectionGroup, BSD sockets) on iOS and iPadOS needs this managed entitlement. Apple grants it on request; the button joins 239.255.77.77:47777 and shows the system's real answer. macOS does not gate multicast behind an entitlement."),
            ("personal-vpn", .personalVPN, "Load VPN preferences", personalVPNBoundary),
            ("network-extensions", .tunnelProviders, "Load tunnel providers", networkExtensionBoundary),
            ("multipath", .multipath, "Open a handover connection",
             "Multipath TCP is requested per connection with NWParameters.multipathServiceType (handover, interactive, aggregate). Aggregate mode only works with Apple's internal servers; the result of the negotiation is not exposed."),
            ("5g-network-slicing", nil, nil,
             "With both slicing entitlements, traffic that sets NWParameters.serviceClass (or URLRequest.networkServiceType) uses the carrier's slice on a supported 5G network. No API reports whether a slice is active."),
        ]
        return rows.compactMap { row in
            guard let capability = CapabilityRegistry.descriptor(for: row.id) else { return nil }
            let state = IdentityEntitlements.state(ofCapability: row.id)
            let present: Bool? = switch state {
            case .provisioned, .declared: true
            case .notProvisioned, .notDeclared: false
            case .unknown: nil
            }
            let probeAvailable = row.probe.map(isProbeSupported) ?? false
            return NetworkCapabilityBoundary(id: row.id, name: capability.name,
                gate: capability.kind.rawValue + " · " + capability.access.title,
                entitlement: IdentityEntitlements.summary(of: state, key: capability.keys.joined(separator: " + ")),
                isProvisioned: present, requirement: capability.requirement, boundary: row.boundary,
                probe: probeAvailable ? row.probe : nil, probeTitle: probeAvailable ? row.probeTitle : nil)
        }
    }
}

#if canImport(CoreLocation) && (os(iOS) || os(macOS))
// Core Location calls back on the thread that created the manager (main); the state is re-read on the main actor.
extension WiFiCapabilityService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            updateLocation()
            if location == .precise || location == .reducedAccuracy { readCurrentNetwork() }
        }
    }
}
#endif
#endif
