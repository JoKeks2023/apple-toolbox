import Foundation
import Combine
import Security

#if canImport(Network) && !os(watchOS)
import Network
#endif
#if canImport(NetworkExtension) && os(iOS)
import NetworkExtension
#endif

// MARK: - Pure helpers (tested)

nonisolated enum VPNDescriptions {
    /// NEVPNStatus raw values.
    static func status(rawValue: Int) -> String {
        WiFiDescriptions.vpnStatus(rawValue: rawValue)
    }

    /// NEVPNConnectionError codes (NEVPNConnectionErrorDomain), reported by fetchLastDisconnectError.
    static func connectionError(code: Int) -> String {
        switch code {
        case 1: "overslept: the system slept too long"
        case 2: "noNetworkAvailable: the device is not connected to a network"
        case 3: "unrecoverableNetworkChange: the network changed and the tunnel could not follow"
        case 4: "configurationFailed: the configuration is invalid"
        case 5: "serverAddressResolutionFailed: the server name could not be resolved"
        case 6: "serverNotResponding: the server did not answer"
        case 7: "serverDead: the server stopped functioning"
        case 8: "authenticationFailed: the server rejected the credentials"
        case 9: "clientCertificateInvalid"
        case 10: "clientCertificateNotYetValid"
        case 11: "clientCertificateExpired"
        case 12: "pluginFailed: the VPN plug-in died"
        case 13: "configurationNotFound"
        case 14: "pluginDisabled: the VPN plug-in could not be found or needs an update"
        case 15: "negotiationFailed: the IKE negotiation failed"
        case 16: "serverDisconnected: the server closed the connection"
        case 17: "serverCertificateInvalid"
        case 18: "serverCertificateNotYetValid"
        case 19: "serverCertificateExpired"
        default: "code \(code)"
        }
    }

    /// NEVPNError codes (NEVPNErrorDomain), reported by saving, loading and starting configurations.
    static func managerError(code: Int) -> String {
        switch code {
        case 1: "configurationInvalid"
        case 2: "configurationDisabled"
        case 3: "connectionFailed"
        case 4: "configurationStale: load the preferences again before changing them"
        case 5: "configurationReadWriteFailed: the person did not allow the VPN configuration, or it could not be written"
        case 6: "configurationUnknown"
        default: "code \(code)"
        }
    }

    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        let name = switch nsError.domain {
        case "NEVPNErrorDomain": managerError(code: nsError.code)
        case "NEVPNConnectionErrorDomain": connectionError(code: nsError.code)
        default: "code \(nsError.code)"
        }
        return "\(nsError.domain) \(nsError.code) (\(name)): \(nsError.localizedDescription)"
    }
}

/// How the IKEv2 client authenticates.
nonisolated enum PersonalVPNAuthentication: String, CaseIterable, Identifiable, Sendable {
    case usernamePassword, sharedSecret

    var id: String { rawValue }
    var title: String {
        switch self {
        case .usernamePassword: "Username and password (EAP)"
        case .sharedSecret: "Shared secret"
        }
    }
}

/// IKE and child SA encryption; only the algorithms current SDKs still accept.
nonisolated enum PersonalVPNEncryption: String, CaseIterable, Identifiable, Sendable {
    case aes256, aes256GCM, chaCha20Poly1305

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aes256: "AES-256"
        case .aes256GCM: "AES-256-GCM"
        case .chaCha20Poly1305: "ChaCha20-Poly1305"
        }
    }
}

nonisolated enum PersonalVPNDiffieHellman: Int, CaseIterable, Identifiable, Sendable {
    case group14 = 14, group19 = 19, group20 = 20, group21 = 21, group31 = 31

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .group14: "Group 14 (MODP 2048)"
        case .group19: "Group 19 (ECP 256)"
        case .group20: "Group 20 (ECP 384)"
        case .group21: "Group 21 (ECP 521)"
        case .group31: "Group 31 (Curve25519)"
        }
    }
}

nonisolated enum PersonalVPNDeadPeerDetection: Int, CaseIterable, Identifiable, Sendable {
    case none = 0, low, medium, high

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: "Off"
        case .low: "Low (every 30 min)"
        case .medium: "Medium (every 10 min)"
        case .high: "High (every minute)"
        }
    }
}

/// What the person entered for the IKEv2 configuration.
nonisolated struct PersonalVPNForm: Equatable, Sendable {
    var server = ""
    var remoteIdentifier = ""
    var localIdentifier = ""
    var username = ""
    var password = ""
    var sharedSecret = ""
    var authentication = PersonalVPNAuthentication.usernamePassword
    var encryption = PersonalVPNEncryption.aes256GCM
    var diffieHellman = PersonalVPNDiffieHellman.group19
    var deadPeerDetection = PersonalVPNDeadPeerDetection.medium
    var disconnectOnSleep = false

    /// The first problem that keeps the configuration from being saved, or nil.
    var problem: String? {
        let server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty else { return "Enter the VPN server (host name or IP address)." }
        guard !server.contains(where: \.isWhitespace), !server.contains("/") else { return "The server is a host name or IP address, without spaces, scheme or path." }
        guard !remoteIdentifier.trimmingCharacters(in: .whitespaces).isEmpty else { return "Enter the remote ID the server identifies itself with (often its host name)." }
        switch authentication {
        case .usernamePassword:
            guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return "Enter the username for EAP authentication." }
            guard !password.isEmpty else { return "Enter the password for EAP authentication." }
        case .sharedSecret:
            guard !sharedSecret.isEmpty else { return "Enter the shared secret." }
        }
        return nil
    }
}

#if canImport(NetworkExtension) && os(iOS)

// MARK: - Keychain references

/// NEVPNProtocol wants persistent keychain references for secrets, never the secrets themselves.
nonisolated enum VPNKeychain {
    static let service = "AppleToolbox.personal-vpn"

    static func persistentReference(for secret: String, account: String) throws -> Data {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecReturnPersistentRef as String] = true
        var result: CFTypeRef?
        let status = SecItemAdd(add as CFDictionary, &result)
        guard status == errSecSuccess, let reference = result as? Data else {
            throw ExperimentServiceError.unavailable("Keychain error \(status) while storing the \(account).")
        }
        return reference
    }

    static func deleteAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

// MARK: - Packet tunnel

/// Installs, starts and stops the configuration of the bundled `AppleToolbox Packet Tunnel` extension, sends test
/// datagrams into the test range and reads the provider's counters with `sendProviderMessage`.
@MainActor
final class PacketTunnelExperimentService: ObservableObject {
    static let extensionPoint = "com.apple.networkextension.packet-tunnel"
    static let configurationName = "Apple Toolbox Test Tunnel"
    static let packetCounts = [1, 5, 20]

    @Published private(set) var status = "Not loaded"
    @Published private(set) var statusRaw = NEVPNStatus.invalid.rawValue
    @Published private(set) var configuration: [NetworkDetailRow] = []
    @Published private(set) var stats: TunnelStats?
    @Published private(set) var output = "Load the preferences to see whether this app has saved a tunnel configuration."
    @Published private(set) var isError = false
    @Published private(set) var isWorking = false
    @Published var packetCount = 5

    private var manager: NETunnelProviderManager?
    private var statusSubscription: AnyCancellable?
    private var poll: Task<Void, Never>?
    private let queue = DispatchQueue(label: "apple-toolbox.tunnel-test")

    /// The bundled provider's bundle identifier, read from its Info.plist.
    var providerBundleIdentifier: String? {
        EmbeddedAppExtension.embedded(extensionPoint: Self.extensionPoint).first?.bundleIdentifier
    }

    var hasConfiguration: Bool { manager != nil }
    var isConnected: Bool { statusRaw == NEVPNStatus.connected.rawValue }
    var isConnectingOrConnected: Bool { [NEVPNStatus.connecting, .connected, .reasserting].map(\.rawValue).contains(statusRaw) }

    // MARK: Preferences

    func load() {
        isWorking = true
        NETunnelProviderManager.loadAllFromPreferences { @Sendable [weak self] managers, error in
            // NETunnelProviderManager is documented as thread safe; the list is handed to the main actor once.
            nonisolated(unsafe) let managers = managers ?? []
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in self?.loaded(managers, error: report) }
        }
    }

    private func loaded(_ managers: [NETunnelProviderManager], error: String?) {
        isWorking = false
        if let error {
            show("loadAllFromPreferences failed: \(error)", isError: true)
            return
        }
        let bundleID = providerBundleIdentifier
        manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleID }
        observeStatus()
        let others = managers.count - (manager == nil ? 0 : 1)
        show(manager == nil
             ? "loadAllFromPreferences: no configuration for the bundled tunnel yet\(others > 0 ? " (\(others) other configuration(s) of this app)" : ""). Install it below; iOS asks once whether Apple Toolbox may add VPN configurations."
             : "Loaded “\(manager?.localizedDescription ?? Self.configurationName)”.", isError: false)
    }

    /// Creates the configuration (or re-saves the existing one) and loads it again, which starting requires.
    func install() {
        guard let bundleID = providerBundleIdentifier else {
            show("No packet tunnel extension is embedded in this build, so there is nothing to configure.", isError: true)
            return
        }
        let manager = manager ?? NETunnelProviderManager()
        let tunnel = NETunnelProviderProtocol()
        tunnel.providerBundleIdentifier = bundleID
        tunnel.serverAddress = TunnelTestRange.serverAddress
        tunnel.disconnectOnSleep = true
        manager.protocolConfiguration = tunnel
        manager.localizedDescription = Self.configurationName
        manager.isEnabled = true
        isWorking = true
        show("saveToPreferences… iOS may ask whether Apple Toolbox may add VPN configurations.", isError: false)
        // NETunnelProviderManager is documented as thread safe; the completion only hands it back to the main actor.
        nonisolated(unsafe) let saving = manager
        manager.saveToPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in self?.saved(saving, error: report) }
        }
    }

    private func saved(_ saved: NETunnelProviderManager, error: String?) {
        if let error {
            isWorking = false
            show("saveToPreferences failed: \(error)\nWithout the Network Extensions entitlement (packet-tunnel-provider) or with the alert declined, iOS refuses the configuration.", isError: true)
            return
        }
        manager = saved
        saved.loadFromPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in
                guard let self else { return }
                self.isWorking = false
                self.observeStatus()
                self.show(report.map { "Saved, but loading it again failed: \($0)" }
                          ?? "Saved “\(Self.configurationName)”. It now appears in Settings › VPN; start it below.", isError: report != nil)
            }
        }
    }

    func remove() {
        guard let manager else { return }
        stopTunnel()
        isWorking = true
        manager.removeFromPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in
                guard let self else { return }
                self.isWorking = false
                if let report {
                    self.show("removeFromPreferences failed: \(report)", isError: true)
                } else {
                    self.manager = nil
                    self.stats = nil
                    self.observeStatus()
                    self.show("Removed the configuration; it is gone from Settings › VPN.", isError: false)
                }
            }
        }
    }

    // MARK: Connection

    func start() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        do {
            try session.startTunnel(options: nil)
            show("startTunnel: the system launches the extension, which claims \(TunnelTestRange.cidr) only.", isError: false)
        } catch {
            show("startTunnel failed: \(VPNDescriptions.describe(error))", isError: true)
        }
    }

    func stopTunnel() {
        (manager?.connection as? NETunnelProviderSession)?.stopTunnel()
    }

    private func observeStatus() {
        statusSubscription = nil
        guard let connection = manager?.connection else {
            statusRaw = NEVPNStatus.invalid.rawValue
            status = VPNDescriptions.status(rawValue: statusRaw)
            configuration = []
            stopPolling()
            return
        }
        statusSubscription = NotificationCenter.default.publisher(for: .NEVPNStatusDidChange, object: connection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.statusChanged() }
        statusChanged()
    }

    private func statusChanged() {
        guard let manager else { return }
        let connection = manager.connection
        statusRaw = connection.status.rawValue
        status = VPNDescriptions.status(rawValue: statusRaw)
        let provider = manager.protocolConfiguration as? NETunnelProviderProtocol
        configuration = [
            NetworkDetailRow(title: "Name", value: manager.localizedDescription ?? "Unnamed"),
            NetworkDetailRow(title: "Provider", value: provider?.providerBundleIdentifier ?? "—"),
            NetworkDetailRow(title: "Enabled", value: manager.isEnabled ? "Yes" : "No"),
            NetworkDetailRow(title: "Routes", value: "\(TunnelTestRange.cidr) only · no DNS settings"),
            NetworkDetailRow(title: "Connected since", value: connection.connectedDate?.formatted(date: .omitted, time: .standard) ?? "—"),
        ]
        if isConnected { startPolling() } else { stopPolling() }
        if connection.status == .disconnected { fetchLastError(connection) }
    }

    private func fetchLastError(_ connection: NEVPNConnection) {
        connection.fetchLastDisconnectError { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            guard let report else { return }
            Task { @MainActor in self?.show("Last disconnect: \(report)", isError: true) }
        }
    }

    // MARK: Test packets and counters

    /// Sends UDP datagrams to 198.18.0.1:9. Only while the tunnel is connected: otherwise they would take the normal route.
    func sendTestPackets() {
        guard isConnected else {
            show("Start the tunnel first. Without it the datagrams would take the normal route instead of the tunnel.", isError: true)
            return
        }
        let count = packetCount
        let connection = NWConnection(host: NWEndpoint.Host(TunnelTestRange.testTarget), port: NWEndpoint.Port(rawValue: TunnelTestRange.testPort)!, using: .udp)
        connection.stateUpdateHandler = { @Sendable [weak self] state in
            switch state {
            case .ready:
                for index in 1...count {
                    connection.send(content: Data("Apple Toolbox tunnel test \(index)/\(count)".utf8), completion: .contentProcessed { _ in })
                }
                // UDP has no acknowledgement; give the provider a moment to read before asking for the counters.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    connection.cancel()
                    Task { @MainActor in
                        self?.show("Sent \(count) UDP datagram(s) to \(TunnelTestRange.testTarget):\(TunnelTestRange.testPort). The provider read them from the tunnel and dropped them.", isError: false)
                        self?.refreshStats()
                    }
                }
            case .failed(let error), .waiting(let error):
                let text = NetworkErrorExplainer.explain(error)
                connection.cancel()
                Task { @MainActor in self?.show("The test datagrams could not be sent: \(text)", isError: true) }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func refreshStats() { send(.stats) }
    func resetStats() { send(.reset) }

    private func send(_ message: TunnelAppMessage) {
        guard let session = manager?.connection as? NETunnelProviderSession, isConnected else { return }
        do {
            try session.sendProviderMessage(message.data) { @Sendable [weak self] response in
                let stats = TunnelStats.decode(response)
                Task { @MainActor in
                    guard let self else { return }
                    if let stats { self.stats = stats } else { self.show("The provider answered \(response?.count ?? 0) bytes that are not counters.", isError: true) }
                }
            }
        } catch {
            show("sendProviderMessage failed: \(VPNDescriptions.describe(error))", isError: true)
        }
    }

    private func startPolling() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshStats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    private func show(_ text: String, isError: Bool) {
        output = text
        self.isError = isError
    }
}

extension PacketTunnelExperimentService: StoppableExperiment {
    /// Leaving the experiment stops the tunnel, so it never keeps running unnoticed.
    var isActive: Bool { isConnectingOrConnected || poll != nil }

    func stop() {
        stopPolling()
        stopTunnel()
    }
}

// MARK: - Personal VPN

/// Configures the built-in IKEv2 client with NEVPNManager. Without a real server the connection fails, and the service
/// shows the error the system reports.
@MainActor
final class PersonalVPNExperimentService: ObservableObject {
    static let configurationName = "Apple Toolbox Personal VPN"

    @Published var form = PersonalVPNForm()
    @Published private(set) var status = "Not loaded"
    @Published private(set) var statusRaw = NEVPNStatus.invalid.rawValue
    @Published private(set) var savedSummary: [NetworkDetailRow] = []
    @Published private(set) var output = "Load the preferences to see whether this app has saved a Personal VPN configuration."
    @Published private(set) var isError = false
    @Published private(set) var isWorking = false

    private var statusSubscription: AnyCancellable?
    private var manager: NEVPNManager { NEVPNManager.shared() }

    var hasConfiguration: Bool { manager.protocolConfiguration != nil }
    var isConnectingOrConnected: Bool { [NEVPNStatus.connecting, .connected, .reasserting].map(\.rawValue).contains(statusRaw) }

    func load() {
        isWorking = true
        manager.loadFromPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in
                guard let self else { return }
                self.isWorking = false
                self.observeStatus()
                self.show(report.map { "loadFromPreferences failed: \($0)" }
                          ?? (self.hasConfiguration ? "Loaded “\(self.manager.localizedDescription ?? "Unnamed")”." : "loadFromPreferences: this app has not saved a Personal VPN configuration."),
                          isError: report != nil)
            }
        }
    }

    /// Writes the IKEv2 configuration. iOS asks once whether Apple Toolbox may add VPN configurations.
    func save() {
        if let problem = form.problem {
            show(problem, isError: true)
            return
        }
        let form = form
        isWorking = true
        manager.loadFromPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in self?.apply(form, loadError: report) }
        }
    }

    private func apply(_ form: PersonalVPNForm, loadError: String?) {
        if let loadError {
            isWorking = false
            show("loadFromPreferences failed: \(loadError)", isError: true)
            return
        }
        let ikev2 = NEVPNProtocolIKEv2()
        ikev2.serverAddress = form.server.trimmingCharacters(in: .whitespacesAndNewlines)
        ikev2.remoteIdentifier = form.remoteIdentifier.trimmingCharacters(in: .whitespaces)
        ikev2.localIdentifier = form.localIdentifier.isEmpty ? nil : form.localIdentifier
        do {
            switch form.authentication {
            case .usernamePassword:
                ikev2.authenticationMethod = .none
                ikev2.useExtendedAuthentication = true
                ikev2.username = form.username
                ikev2.passwordReference = try VPNKeychain.persistentReference(for: form.password, account: "password")
            case .sharedSecret:
                ikev2.authenticationMethod = .sharedSecret
                ikev2.sharedSecretReference = try VPNKeychain.persistentReference(for: form.sharedSecret, account: "shared-secret")
                if !form.username.isEmpty {
                    ikev2.useExtendedAuthentication = true
                    ikev2.username = form.username
                    ikev2.passwordReference = try VPNKeychain.persistentReference(for: form.password, account: "password")
                }
            }
        } catch {
            isWorking = false
            show("Storing the secret failed: \(error.localizedDescription)", isError: true)
            return
        }
        for parameters in [ikev2.ikeSecurityAssociationParameters, ikev2.childSecurityAssociationParameters] {
            parameters.encryptionAlgorithm = switch form.encryption {
            case .aes256: .algorithmAES256
            case .aes256GCM: .algorithmAES256GCM
            case .chaCha20Poly1305: .algorithmChaCha20Poly1305
            }
            parameters.integrityAlgorithm = .SHA256
            parameters.diffieHellmanGroup = NEVPNIKEv2DiffieHellmanGroup(rawValue: form.diffieHellman.rawValue) ?? .group19
        }
        ikev2.deadPeerDetectionRate = NEVPNIKEv2DeadPeerDetectionRate(rawValue: form.deadPeerDetection.rawValue) ?? .medium
        ikev2.disconnectOnSleep = form.disconnectOnSleep
        manager.protocolConfiguration = ikev2
        manager.localizedDescription = Self.configurationName
        manager.isEnabled = true
        manager.saveToPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in
                guard let self else { return }
                self.isWorking = false
                self.observeStatus()
                self.show(report.map { "saveToPreferences failed: \($0)\nWithout the Personal VPN entitlement (allow-vpn) or with the alert declined, iOS refuses the configuration." }
                          ?? "Saved “\(Self.configurationName)” (IKEv2 to \(form.server)). Connect below; without a reachable IKEv2 server the attempt fails and the system's error appears here.",
                          isError: report != nil)
            }
        }
    }

    func connect() {
        do {
            try manager.connection.startVPNTunnel()
            show("startVPNTunnel: the IKEv2 client is contacting \(form.server.isEmpty ? "the saved server" : form.server)…", isError: false)
        } catch {
            show("startVPNTunnel failed: \(VPNDescriptions.describe(error))", isError: true)
        }
    }

    func disconnect() {
        manager.connection.stopVPNTunnel()
    }

    func remove() {
        disconnect()
        isWorking = true
        manager.removeFromPreferences { @Sendable [weak self] error in
            let report = error.map(VPNDescriptions.describe)
            Task { @MainActor in
                guard let self else { return }
                self.isWorking = false
                if report == nil { VPNKeychain.deleteAll() }
                self.observeStatus()
                self.show(report.map { "removeFromPreferences failed: \($0)" } ?? "Removed the Personal VPN configuration and its keychain secrets.", isError: report != nil)
            }
        }
    }

    private func observeStatus() {
        statusSubscription = NotificationCenter.default.publisher(for: .NEVPNStatusDidChange, object: manager.connection)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.statusChanged() }
        statusChanged()
    }

    private func statusChanged() {
        let connection = manager.connection
        let previous = statusRaw
        statusRaw = connection.status.rawValue
        status = VPNDescriptions.status(rawValue: statusRaw)
        if let ikev2 = manager.protocolConfiguration as? NEVPNProtocolIKEv2 {
            savedSummary = [
                NetworkDetailRow(title: "Name", value: manager.localizedDescription ?? "Unnamed"),
                NetworkDetailRow(title: "Server", value: ikev2.serverAddress ?? "—"),
                NetworkDetailRow(title: "Remote ID", value: ikev2.remoteIdentifier ?? "—"),
                NetworkDetailRow(title: "Authentication", value: ikev2.authenticationMethod == .sharedSecret ? "Shared secret" : "EAP (\(ikev2.username ?? "no user"))"),
                NetworkDetailRow(title: "Enabled", value: manager.isEnabled ? "Yes" : "No"),
            ]
        } else {
            savedSummary = []
        }
        // A connection attempt that ended: ask the system why.
        if connection.status == .disconnected, previous != NEVPNStatus.disconnected.rawValue, previous != NEVPNStatus.invalid.rawValue {
            connection.fetchLastDisconnectError { @Sendable [weak self] error in
                let report = error.map(VPNDescriptions.describe) ?? "no error recorded"
                Task { @MainActor in self?.show("Disconnected. fetchLastDisconnectError: \(report)", isError: error != nil) }
            }
        }
    }

    private func show(_ text: String, isError: Bool) {
        output = text
        self.isError = isError
    }
}

extension PersonalVPNExperimentService: StoppableExperiment {
    var isActive: Bool { isConnectingOrConnected }
    func stop() { disconnect() }
}
#endif
