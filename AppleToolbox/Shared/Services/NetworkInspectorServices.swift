import Foundation
import Combine

#if canImport(Network)
import Network
#endif
#if canImport(Security)
import Security
#endif

// MARK: - Shared values (pure, tested)

nonisolated struct NetworkInterfaceResult: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let index: Int
}

/// One line in a live network log.
nonisolated struct NetworkLogEntry: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case state, sent, received, info, error }

    let id = UUID()
    let date: Date
    let kind: Kind
    let text: String

    init(_ kind: Kind, _ text: String, date: Date = Date()) {
        self.kind = kind
        self.text = text
        self.date = date
    }

    var symbol: String {
        switch kind {
        case .state: "◆"
        case .sent: "→"
        case .received: "←"
        case .info: "·"
        case .error: "✕"
        }
    }
}

nonisolated enum NetworkLogFormatter {
    static let capacity = 200

    static func appending(_ entry: NetworkLogEntry, to log: [NetworkLogEntry]) -> [NetworkLogEntry] {
        Array((log + [entry]).suffix(capacity))
    }

    /// Newest entry last, like a terminal.
    static func text(_ log: [NetworkLogEntry], limit: Int = 40, placeholder: String) -> String {
        guard !log.isEmpty else { return placeholder }
        return log.suffix(limit).map { entry in
            "\(entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))) \(entry.symbol) \(entry.text)"
        }.joined(separator: "\n")
    }
}

/// A title/value pair for connection details such as endpoints or TLS parameters.
nonisolated struct NetworkDetailRow: Identifiable, Equatable, Sendable {
    let title: String
    let value: String
    var id: String { title }
}

/// Transports offered by the NWConnection client.
nonisolated enum NetworkTransport: String, CaseIterable, Identifiable, Sendable {
    case tcp, udp, tls

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tcp: "TCP"
        case .udp: "UDP"
        case .tls: "TLS over TCP"
        }
    }
    var defaultPort: UInt16 {
        switch self {
        case .tcp: 80
        case .udp: 53
        case .tls: 443
        }
    }
}

/// Appended to each message the client sends; line-based protocols (HTTP, SMTP, echo servers) need one.
nonisolated enum LineEnding: String, CaseIterable, Identifiable, Sendable {
    case none, lf, crlf

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .lf: "LF (\\n)"
        case .crlf: "CRLF (\\r\\n)"
        }
    }
    var suffix: String {
        switch self {
        case .none: ""
        case .lf: "\n"
        case .crlf: "\r\n"
        }
    }
}

/// Validates the free-text host and port fields before a connection is created.
nonisolated enum NetworkTargetParser {
    /// Trims whitespace, a URL scheme, a path and IPv6 brackets, so "https://example.com/a" becomes "example.com".
    static func host(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeEnd = host.range(of: "://") { host = String(host[schemeEnd.upperBound...]) }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host.isEmpty ? nil : host
    }

    static func port(_ text: String) -> UInt16? {
        guard let value = UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return value
    }
}

/// Renders received bytes: printable UTF-8 as text, anything else as a hex preview.
nonisolated enum NetworkPayloadFormatter {
    static func describe(_ data: Data, limit: Int = 600) -> String {
        guard !data.isEmpty else { return "(empty)" }
        if let text = String(data: data, encoding: .utf8), text.unicodeScalars.allSatisfy(isPrintable) {
            let visible = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
            guard visible.count > limit else { return visible }
            return String(visible.prefix(limit)) + "… (\(visible.count - limit) more characters)"
        }
        return hex(data, limit: 32)
    }

    static func hex(_ data: Data, limit: Int) -> String {
        let bytes = data.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
        return data.count > limit ? "\(bytes) … (\(data.count) bytes, binary)" : "\(bytes) (binary)"
    }

    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\t" || !(scalar.properties.generalCategory == .control)
    }
}

/// IANA names for the TLS values Network.framework reports as raw `tls_protocol_version_t` / `tls_ciphersuite_t`.
nonisolated enum TLSDescription {
    static func version(_ raw: UInt16) -> String {
        switch raw {
        case 0x0301: "TLS 1.0"
        case 0x0302: "TLS 1.1"
        case 0x0303: "TLS 1.2"
        case 0x0304: "TLS 1.3"
        case 0xFEFF: "DTLS 1.0"
        case 0xFEFD: "DTLS 1.2"
        default: String(format: "Unknown (0x%04X)", raw)
        }
    }

    static func cipherSuite(_ raw: UInt16) -> String {
        let names: [UInt16: String] = [
            0x1301: "TLS_AES_128_GCM_SHA256", 0x1302: "TLS_AES_256_GCM_SHA384", 0x1303: "TLS_CHACHA20_POLY1305_SHA256",
            0xC02B: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", 0xC02C: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
            0xC02F: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", 0xC030: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
            0xCCA9: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256", 0xCCA8: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
            0xC009: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA", 0xC00A: "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA",
            0xC013: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA", 0xC014: "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA",
            0x009C: "TLS_RSA_WITH_AES_128_GCM_SHA256", 0x009D: "TLS_RSA_WITH_AES_256_GCM_SHA384",
            0x002F: "TLS_RSA_WITH_AES_128_CBC_SHA", 0x0035: "TLS_RSA_WITH_AES_256_CBC_SHA",
        ]
        return names[raw] ?? String(format: "0x%04X", raw)
    }
}

/// Bonjour service types the browser offers. iOS only lets an app browse types listed in NSBonjourServices,
/// so every preset must also be declared in Info.plist.
nonisolated struct BonjourServiceType: Identifiable, Hashable, Sendable {
    let type: String
    let title: String
    var id: String { type }

    /// The echo listener of the Network Inspector. It deliberately does not reuse `_apple-toolbox._tcp`, which the
    /// MultipeerConnectivity experiment already advertises (service type "apple-toolbox").
    static let echo = BonjourServiceType(type: "_toolbox-echo._tcp", title: "Apple Toolbox echo listener")

    static let presets: [BonjourServiceType] = [
        echo,
        BonjourServiceType(type: "_apple-toolbox._tcp", title: "Apple Toolbox Multipeer peers"),
        BonjourServiceType(type: "_http._tcp", title: "Web servers"),
        BonjourServiceType(type: "_ipp._tcp", title: "Printers (IPP / AirPrint)"),
        BonjourServiceType(type: "_airplay._tcp", title: "AirPlay receivers"),
        BonjourServiceType(type: "_raop._tcp", title: "AirPlay audio (RAOP)"),
        BonjourServiceType(type: "_companion-link._tcp", title: "Apple devices (Companion Link)"),
        BonjourServiceType(type: "_hap._tcp", title: "HomeKit accessories (IP)"),
        BonjourServiceType(type: "_matter._tcp", title: "Matter nodes"),
        BonjourServiceType(type: "_ssh._tcp", title: "SSH servers"),
        BonjourServiceType(type: "_smb._tcp", title: "SMB file sharing"),
        BonjourServiceType(type: "_googlecast._tcp", title: "Google Cast receivers"),
    ]

    /// `_name._tcp` or `_name._udp` with a 1–15 character name of letters, digits and hyphens (RFC 6335).
    static func isValid(_ type: String) -> Bool {
        let parts = type.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].hasPrefix("_"), parts[1] == "_tcp" || parts[1] == "_udp" else { return false }
        let name = parts[0].dropFirst()
        return (1...15).contains(name.count) && name.first != "-" && name.last != "-"
            && name.allSatisfy { ($0.isASCII && $0.isLetter) || $0.isNumber || $0 == "-" }
    }

    static func declaredTypes(in bundle: Bundle = .main) -> [String] {
        bundle.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] ?? []
    }
}

/// Explains Network.framework errors, in particular the local network privacy and Bonjour declaration failures.
nonisolated enum NetworkErrorExplainer {
    /// dns_sd.h: kDNSServiceErr_PolicyDenied, kDNSServiceErr_NoAuth, kDNSServiceErr_NoSuchRecord, kDNSServiceErr_NoSuchName.
    static let policyDenied: Int32 = -65570
    static let noAuth: Int32 = -65555
    static let noSuchRecord: Int32 = -65554
    static let noSuchName: Int32 = -65538

    #if canImport(Network)
    static func isLocalNetworkDenial(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == policyDenied }
        return false
    }

    static func explain(_ error: NWError) -> String {
        switch error {
        case .dns(let code):
            switch code {
            case policyDenied: return "DNS-SD \(code) PolicyDenied: local network access is denied for Apple Toolbox. Allow it in Settings › Privacy & Security › Local Network."
            case noAuth: return "DNS-SD \(code) NoAuth: this Bonjour service type is not declared in NSBonjourServices, so the system refuses it."
            case noSuchRecord: return "DNS-SD \(code) NoSuchRecord: the name did not resolve."
            case noSuchName: return "DNS-SD \(code) NoSuchName: the name does not exist."
            default: return "DNS-SD error \(code)."
            }
        case .posix(let code):
            let base = "POSIX \(code.rawValue) (\(String(cString: strerror(code.rawValue))))"
            switch code {
            case .ECONNREFUSED: return base + ": nothing is listening on that port."
            case .ETIMEDOUT: return base + ": the peer did not answer in time."
            case .ENETUNREACH, .EHOSTUNREACH: return base + ": no route to that address from the current path."
            case .ENETDOWN: return base + ": the network is down."
            case .EPERM, .EACCES: return base + ": the system refused the operation, typically a missing entitlement or denied local network access."
            case .ECONNRESET: return base + ": the peer reset the connection."
            case .EADDRINUSE: return base + ": the address or port is already in use."
            default: return base + "."
            }
        case .tls(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "TLS failure"
            return "TLS \(status): \(message)."
        case .wifiAware(let code):
            return "Wi-Fi Aware error \(code)."
        @unknown default:
            return error.debugDescription
        }
    }
    #endif
}

// MARK: - Path snapshot

/// A Sendable copy of an NWPath, created on the monitor's queue and handed to the main actor.
nonisolated struct NetworkPathSnapshot: Equatable, Sendable {
    let status: String
    let unsatisfiedReason: String?
    let primaryInterface: String
    let interfaces: [NetworkInterfaceResult]
    let isExpensive: Bool
    let isConstrained: Bool
    let isUltraConstrained: Bool
    let linkQuality: String
    let supportsIPv4: Bool
    let supportsIPv6: Bool
    let supportsDNS: Bool
    let gateways: [String]
    let localEndpoint: String?
    let remoteEndpoint: String?

    /// Short summary used by logs and the Spatial Link view, e.g. "Satisfied via Wi-Fi (en0)".
    var summary: String {
        guard status == "Satisfied" else { return unsatisfiedReason.map { "\(status): \($0)" } ?? status }
        return "\(status) via \(primaryInterface)"
    }
}

#if canImport(Network)
nonisolated extension NetworkPathSnapshot {
    init(path: NWPath) {
        status = Self.title(path.status)
        unsatisfiedReason = path.status == .unsatisfied ? Self.title(path.unsatisfiedReason) : nil
        interfaces = path.availableInterfaces.map {
            NetworkInterfaceResult(id: "\($0.name)-\($0.index)", name: $0.name, type: Self.title($0.type), index: $0.index)
        }
        primaryInterface = path.availableInterfaces.first.map { "\(Self.title($0.type)) (\($0.name))" } ?? "None"
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        isUltraConstrained = path.isUltraConstrained
        linkQuality = Self.title(path.linkQuality)
        supportsIPv4 = path.supportsIPv4
        supportsIPv6 = path.supportsIPv6
        supportsDNS = path.supportsDNS
        gateways = path.gateways.map(\.debugDescription)
        localEndpoint = path.localEndpoint?.debugDescription
        remoteEndpoint = path.remoteEndpoint?.debugDescription
    }

    static func title(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied: "Satisfied"
        case .unsatisfied: "Unsatisfied"
        case .requiresConnection: "Requires connection"
        @unknown default: "Unknown"
        }
    }

    static func title(_ reason: NWPath.UnsatisfiedReason) -> String {
        switch reason {
        case .notAvailable: "No usable network"
        case .cellularDenied: "Cellular data is turned off for this app"
        case .wifiDenied: "Wi-Fi (WLAN) access is turned off for this app"
        case .localNetworkDenied: "Local network access is denied"
        case .vpnInactive: "A required VPN is not active"
        @unknown default: "Unknown reason"
        }
    }

    static func title(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wiredEthernet: "Ethernet"
        case .loopback: "Loopback"
        case .other: "Other"
        @unknown default: "Unknown"
        }
    }

    static func title(_ quality: NWPath.LinkQuality) -> String {
        switch quality {
        case .unknown: "Unknown"
        case .minimal: "Minimal"
        case .moderate: "Moderate"
        case .good: "Good"
        @unknown default: "Unknown"
        }
    }
}
#endif

// MARK: - Path monitor

/// Live NWPathMonitor state. A cancelled NWPathMonitor cannot be restarted, so every start creates a new one.
@MainActor
final class NetworkExperimentService: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var snapshot: NetworkPathSnapshot?
    /// Status and interface changes while the monitor runs (network transitions).
    @Published private(set) var transitions: [NetworkLogEntry] = []
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "apple-toolbox.network-path")
    #endif

    func start() {
        #if canImport(Network)
        guard !isMonitoring else { return }
        isMonitoring = true
        transitions = []
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let snapshot = NetworkPathSnapshot(path: path)
            Task { @MainActor in self?.apply(snapshot) }
        }
        monitor.start(queue: queue)
        #endif
    }

    func stop() {
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
        isMonitoring = false
    }

    private func apply(_ new: NetworkPathSnapshot) {
        guard isMonitoring else { return }
        let old = snapshot
        snapshot = new
        if old?.summary != new.summary || old?.isExpensive != new.isExpensive || old?.isConstrained != new.isConstrained {
            var flags: [String] = []
            if new.isExpensive { flags.append("expensive") }
            if new.isConstrained { flags.append("constrained") }
            let suffix = flags.isEmpty ? "" : " · " + flags.joined(separator: ", ")
            transitions = NetworkLogFormatter.appending(NetworkLogEntry(.state, new.summary + suffix), to: transitions)
        }
    }
}

// MARK: - NWConnection client

@MainActor
final class NetworkClientService: ObservableObject {
    @Published private(set) var state = "Idle"
    @Published private(set) var isActive = false
    @Published private(set) var isReady = false
    @Published private(set) var details: [NetworkDetailRow] = []
    @Published private(set) var log: [NetworkLogEntry] = []
    @Published private(set) var sawLocalNetworkDenial = false
    /// Host for an HTTP `Host:` header; nil when the target is a Bonjour service.
    @Published private(set) var httpHost: String?
    private(set) var transport = NetworkTransport.tcp

    #if canImport(Network)
    private var connection: NWConnection?
    /// Identifies the current connection so late callbacks from a cancelled one are ignored.
    private var generation = 0
    private let queue = DispatchQueue(label: "apple-toolbox.network-client")
    #endif

    func connect(host rawHost: String, port rawPort: String, transport: NetworkTransport) {
        #if canImport(Network)
        guard let host = NetworkTargetParser.host(rawHost) else { append(.error, "Enter a host name or IP address."); return }
        guard let port = NetworkTargetParser.port(rawPort) else { append(.error, "Enter a port between 1 and 65535."); return }
        start(NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!), label: "\(host):\(port)", httpHost: host, transport: transport)
        #else
        append(.error, "Network.framework is not available on this platform.")
        #endif
    }

    #if canImport(Network)
    /// Connects to an endpoint found by the Bonjour browser; Network.framework resolves the service itself.
    func connect(to endpoint: NWEndpoint, label: String) {
        start(endpoint, label: label, httpHost: nil, transport: .tcp)
    }

    private func start(_ endpoint: NWEndpoint, label: String, httpHost: String?, transport: NetworkTransport) {
        cancelConnection()
        let parameters: NWParameters = switch transport {
        case .tcp: .tcp
        case .udp: .udp
        case .tls: .tls
        }
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        generation += 1
        let generation = generation
        self.connection = connection
        self.transport = transport
        self.httpHost = httpHost
        details = []
        isActive = true
        isReady = false
        state = "Setup"
        append(.info, "Connecting to \(label) over \(transport.title)…")

        connection.stateUpdateHandler = { @Sendable [weak self] state in
            Task { @MainActor in self?.handle(state, generation: generation) }
        }
        connection.pathUpdateHandler = { @Sendable [weak self] path in
            let snapshot = NetworkPathSnapshot(path: path)
            Task { @MainActor in self?.log(generation, .info, "Path: \(snapshot.summary)") }
        }
        connection.viabilityUpdateHandler = { @Sendable [weak self] isViable in
            Task { @MainActor in self?.log(generation, .info, isViable ? "Path is viable again." : "Path is not viable; the connection stalls until a usable path returns.") }
        }
        connection.betterPathUpdateHandler = { @Sendable [weak self] hasBetterPath in
            guard hasBetterPath else { return }
            Task { @MainActor in self?.log(generation, .info, "A better path is available (for example Wi-Fi instead of cellular).") }
        }
        connection.start(queue: queue)
    }

    private func handle(_ newState: NWConnection.State, generation: Int) {
        guard generation == self.generation, let connection else { return }
        switch newState {
        case .setup:
            state = "Setup"
        case .preparing:
            state = "Preparing"
            append(.state, "preparing: resolving the name and running the handshakes")
        case .waiting(let error):
            state = "Waiting"
            sawLocalNetworkDenial = sawLocalNetworkDenial || NetworkErrorExplainer.isLocalNetworkDenial(error)
            append(.state, "waiting: \(NetworkErrorExplainer.explain(error)) Network.framework retries when the path changes.")
        case .ready:
            state = "Ready"
            isReady = true
            details = ConnectionInspector.details(of: connection)
            append(.state, "ready")
            receiveNext(on: connection, generation: generation)
        case .failed(let error):
            state = "Failed"
            sawLocalNetworkDenial = sawLocalNetworkDenial || NetworkErrorExplainer.isLocalNetworkDenial(error)
            append(.error, "failed: \(NetworkErrorExplainer.explain(error))")
            connection.cancel()
            finish()
        case .cancelled:
            state = "Cancelled"
            append(.state, "cancelled")
            finish()
        @unknown default:
            append(.state, "unknown state")
        }
    }

    private func receiveNext(on connection: NWConnection, generation: Int) {
        if transport == .udp {
            connection.receiveMessage { @Sendable [weak self] data, _, _, error in
                Task { @MainActor in self?.received(data, isComplete: false, error: error, generation: generation) }
            }
        } else {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { @Sendable [weak self] data, _, isComplete, error in
                Task { @MainActor in self?.received(data, isComplete: isComplete, error: error, generation: generation) }
            }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, error: NWError?, generation: Int) {
        guard generation == self.generation, let connection else { return }
        if let data, !data.isEmpty {
            append(.received, "\(data.count) B: \(NetworkPayloadFormatter.describe(data))")
        }
        if let error {
            append(.error, "receive: \(NetworkErrorExplainer.explain(error))")
            return
        }
        if isComplete {
            append(.info, "The peer closed its side of the stream.")
            return
        }
        receiveNext(on: connection, generation: generation)
    }

    private func log(_ generation: Int, _ kind: NetworkLogEntry.Kind, _ text: String) {
        guard generation == self.generation else { return }
        append(kind, text)
    }

    private func finish() {
        connection?.stateUpdateHandler = nil
        connection?.pathUpdateHandler = nil
        connection?.viabilityUpdateHandler = nil
        connection?.betterPathUpdateHandler = nil
        connection = nil
        isActive = false
        isReady = false
    }

    private func cancelConnection() {
        guard let connection else { return }
        generation += 1 // Ignore the old connection's late callbacks.
        connection.cancel()
        finish()
    }
    #endif

    func send(_ text: String, lineEnding: LineEnding) {
        #if canImport(Network)
        guard let connection, isReady else { append(.error, "Connect first; nothing was sent."); return }
        let payload = text + lineEnding.suffix
        guard !payload.isEmpty else { append(.error, "Enter a message or choose a line ending."); return }
        let data = Data(payload.utf8)
        let generation = generation
        let preview = NetworkPayloadFormatter.describe(data)
        connection.send(content: data, completion: .contentProcessed { @Sendable [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.log(generation, .error, "send: \(NetworkErrorExplainer.explain(error))")
                } else {
                    self?.log(generation, .sent, "\(data.count) B: \(preview)")
                }
            }
        })
        #endif
    }

    /// A minimal HTTP/1.1 request, handy to see a TCP or TLS server answer.
    func sendHTTPHead() {
        guard let httpHost else { append(.error, "An HTTP request needs a host name."); return }
        send("HEAD / HTTP/1.1\r\nHost: \(httpHost)\r\nUser-Agent: AppleToolbox\r\nConnection: close\r\n", lineEnding: .crlf)
    }

    func stop() {
        #if canImport(Network)
        guard let connection else { return }
        append(.info, "Cancelling the connection…")
        connection.cancel() // The .cancelled state finishes the cleanup.
        #endif
    }

    func clearLog() { log = [] }

    private func append(_ kind: NetworkLogEntry.Kind, _ text: String) {
        log = NetworkLogFormatter.appending(NetworkLogEntry(kind, text), to: log)
    }
}

#if canImport(Network)
/// Reads endpoints, interface and TLS parameters of a ready connection. Network.framework objects are thread-safe;
/// the helpers are nonisolated so the Security callbacks below never assume the main actor.
nonisolated enum ConnectionInspector {
    static func details(of connection: NWConnection) -> [NetworkDetailRow] {
        var rows: [NetworkDetailRow] = []
        if let path = connection.currentPath {
            if let local = path.localEndpoint { rows.append(NetworkDetailRow(title: "Local endpoint", value: local.debugDescription)) }
            if let remote = path.remoteEndpoint { rows.append(NetworkDetailRow(title: "Remote endpoint", value: remote.debugDescription)) }
            if let interface = path.availableInterfaces.first {
                rows.append(NetworkDetailRow(title: "Interface", value: "\(NetworkPathSnapshot.title(interface.type)) (\(interface.name))"))
            }
            rows.append(NetworkDetailRow(title: "Expensive · constrained", value: "\(path.isExpensive ? "Yes" : "No") · \(path.isConstrained ? "Yes" : "No")"))
        }
        rows.append(contentsOf: tlsDetails(of: connection))
        return rows
    }

    static func tlsDetails(of connection: NWConnection) -> [NetworkDetailRow] {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return [] }
        let security = metadata.securityProtocolMetadata
        var rows = [
            NetworkDetailRow(title: "TLS version", value: TLSDescription.version(sec_protocol_metadata_get_negotiated_tls_protocol_version(security).rawValue)),
            NetworkDetailRow(title: "Cipher suite", value: TLSDescription.cipherSuite(sec_protocol_metadata_get_negotiated_tls_ciphersuite(security).rawValue)),
        ]
        if let alpn = sec_protocol_metadata_copy_negotiated_protocol(security) {
            rows.append(NetworkDetailRow(title: "ALPN protocol", value: String(cString: alpn)))
            free(UnsafeMutablePointer(mutating: alpn))
        } else {
            rows.append(NetworkDetailRow(title: "ALPN protocol", value: "None negotiated"))
        }
        if let serverName = sec_protocol_metadata_copy_server_name(security) {
            rows.append(NetworkDetailRow(title: "Server name (SNI)", value: String(cString: serverName)))
            free(UnsafeMutablePointer(mutating: serverName))
        }
        var subjects: [String] = []
        let accessible = sec_protocol_metadata_access_peer_certificate_chain(security) { certificate in
            let reference = sec_certificate_copy_ref(certificate).takeRetainedValue()
            subjects.append(SecCertificateCopySubjectSummary(reference) as String? ?? "Unnamed certificate")
        }
        rows.append(NetworkDetailRow(title: "Peer certificates", value: accessible && !subjects.isEmpty
            ? subjects.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")
            : "Not accessible"))
        return rows
    }
}
#endif

// MARK: - NWListener (echo server)

@MainActor
final class NetworkListenerService: ObservableObject {
    static let maximumConnections = 8

    @Published private(set) var state = "Stopped"
    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16?
    @Published private(set) var registeredService: String?
    @Published private(set) var activeConnections = 0
    @Published private(set) var totalConnections = 0
    @Published private(set) var log: [NetworkLogEntry] = []
    @Published private(set) var sawLocalNetworkDenial = false

    #if canImport(Network)
    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var generation = 0
    private let queue = DispatchQueue(label: "apple-toolbox.network-listener")
    #endif

    func start() {
        #if canImport(Network)
        stop()
        generation += 1
        let generation = generation
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            let txt = NWTXTRecord(["app": "apple-toolbox", "platform": CurrentPlatform.value.rawValue])
            listener.service = NWListener.Service(name: ContinuityExperimentService.deviceName, type: BonjourServiceType.echo.type, txtRecord: txt)
            listener.stateUpdateHandler = { @Sendable [weak self] state in
                Task { @MainActor in self?.handle(state, generation: generation) }
            }
            listener.serviceRegistrationUpdateHandler = { @Sendable [weak self] change in
                Task { @MainActor in self?.handle(change, generation: generation) }
            }
            listener.newConnectionHandler = { @Sendable [weak self] connection in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    self.accept(connection, generation: generation)
                }
            }
            self.listener = listener
            isRunning = true
            state = "Setup"
            totalConnections = 0
            append(.info, "Starting a TCP listener on an automatic port and advertising \(BonjourServiceType.echo.type)…")
            listener.start(queue: queue)
        } catch {
            append(.error, "NWListener could not be created: \((error as? NWError).map(NetworkErrorExplainer.explain) ?? error.localizedDescription)")
        }
        #else
        append(.error, "Network.framework is not available on this platform.")
        #endif
    }

    func stop() {
        #if canImport(Network)
        guard let listener else { return }
        generation += 1
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.serviceRegistrationUpdateHandler = nil
        listener.cancel()
        connections.values.forEach { $0.cancel() }
        connections = [:]
        self.listener = nil
        activeConnections = 0
        port = nil
        registeredService = nil
        isRunning = false
        state = "Stopped"
        append(.state, "listener cancelled")
        #endif
    }

    func clearLog() { log = [] }

    #if canImport(Network)
    private func handle(_ newState: NWListener.State, generation: Int) {
        guard generation == self.generation, let listener else { return }
        switch newState {
        case .setup:
            state = "Setup"
        case .waiting(let error):
            state = "Waiting"
            sawLocalNetworkDenial = sawLocalNetworkDenial || NetworkErrorExplainer.isLocalNetworkDenial(error)
            append(.state, "waiting: \(NetworkErrorExplainer.explain(error))")
        case .ready:
            state = "Ready"
            port = listener.port?.rawValue
            append(.state, "ready on TCP port \(port.map(String.init) ?? "?")")
        case .failed(let error):
            state = "Failed"
            sawLocalNetworkDenial = sawLocalNetworkDenial || NetworkErrorExplainer.isLocalNetworkDenial(error)
            append(.error, "failed: \(NetworkErrorExplainer.explain(error))")
            stop()
            state = "Failed"
        case .cancelled:
            state = "Stopped"
        @unknown default:
            append(.state, "unknown state")
        }
    }

    private func handle(_ change: NWListener.ServiceRegistrationChange, generation: Int) {
        guard generation == self.generation else { return }
        switch change {
        case .add(let endpoint):
            registeredService = endpoint.debugDescription
            append(.state, "Bonjour registered \(endpoint.debugDescription)")
        case .remove(let endpoint):
            registeredService = nil
            append(.state, "Bonjour removed \(endpoint.debugDescription)")
        @unknown default:
            break
        }
    }

    private func accept(_ connection: NWConnection, generation: Int) {
        guard generation == self.generation, connections.count < Self.maximumConnections else {
            connection.cancel()
            if generation == self.generation { append(.error, "Rejected a client: \(Self.maximumConnections) connections are already open.") }
            return
        }
        totalConnections += 1
        let id = totalConnections
        connections[id] = connection
        activeConnections = connections.count
        append(.state, "#\(id) client \(connection.endpoint.debugDescription) connected")

        let report: @Sendable (NetworkLogEntry.Kind, String) -> Void = { [weak self] kind, text in
            Task { @MainActor in self?.log(generation, kind, "#\(id) \(text)") }
        }
        connection.stateUpdateHandler = { @Sendable [weak self] state in
            switch state {
            case .failed(let error):
                report(.error, "failed: \(NetworkErrorExplainer.explain(error))")
                connection.cancel()
            case .cancelled:
                connection.stateUpdateHandler = nil // Breaks the handler's reference to its own connection.
                Task { @MainActor in self?.closed(id, generation: generation) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        Self.echo(on: connection, report: report)
    }

    /// Runs on the listener's queue: every received chunk is sent straight back.
    nonisolated private static func echo(on connection: NWConnection, report: @escaping @Sendable (NetworkLogEntry.Kind, String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { @Sendable data, _, isComplete, error in
            if let data, !data.isEmpty {
                connection.send(content: data, completion: .contentProcessed { @Sendable sendError in
                    if let sendError { report(.error, "echo failed: \(NetworkErrorExplainer.explain(sendError))") }
                })
                report(.received, "echoed \(data.count) B: \(NetworkPayloadFormatter.describe(data))")
            }
            if let error {
                report(.error, "receive: \(NetworkErrorExplainer.explain(error))")
                connection.cancel()
            } else if isComplete {
                report(.info, "client closed its side; closing")
                connection.cancel()
            } else {
                echo(on: connection, report: report)
            }
        }
    }

    private func closed(_ id: Int, generation: Int) {
        guard generation == self.generation, connections.removeValue(forKey: id) != nil else { return }
        activeConnections = connections.count
        append(.state, "#\(id) disconnected")
    }

    private func log(_ generation: Int, _ kind: NetworkLogEntry.Kind, _ text: String) {
        guard generation == self.generation else { return }
        append(kind, text)
    }
    #endif

    private func append(_ kind: NetworkLogEntry.Kind, _ text: String) {
        log = NetworkLogFormatter.appending(NetworkLogEntry(kind, text), to: log)
    }
}

// MARK: - NWBrowser (Bonjour)

nonisolated struct BonjourResult: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let domain: String
    let interfaces: [String]
    let txtRecord: [String]
    #if canImport(Network)
    let endpoint: NWEndpoint
    #endif
}

#if canImport(Network)
nonisolated extension BonjourResult {
    init(_ result: NWBrowser.Result) {
        endpoint = result.endpoint
        id = result.endpoint.debugDescription
        if case .service(let name, let type, let domain, _) = result.endpoint {
            self.name = name
            self.type = type
            self.domain = domain
        } else {
            name = result.endpoint.debugDescription
            type = ""
            domain = ""
        }
        interfaces = result.interfaces.map { "\($0.name) (\(NetworkPathSnapshot.title($0.type)))" }
        if case .bonjour(let record) = result.metadata {
            txtRecord = record.dictionary.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        } else {
            txtRecord = []
        }
    }
}
#endif

@MainActor
final class BonjourBrowserService: ObservableObject {
    @Published private(set) var state = "Stopped"
    @Published private(set) var isBrowsing = false
    @Published private(set) var browsedType: String?
    @Published private(set) var results: [BonjourResult] = []
    @Published private(set) var message = "Choose a service type and start browsing."
    @Published private(set) var sawLocalNetworkDenial = false

    #if canImport(Network)
    private var browser: NWBrowser?
    private var generation = 0
    private let queue = DispatchQueue(label: "apple-toolbox.bonjour-browser")
    #endif

    func start(type rawType: String) {
        #if canImport(Network)
        stop()
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BonjourServiceType.isValid(type) else {
            message = "“\(type)” is not a valid Bonjour service type. Use _name._tcp or _name._udp."
            return
        }
        generation += 1
        let generation = generation
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: parameters)
        browser.stateUpdateHandler = { @Sendable [weak self] state in
            Task { @MainActor in self?.handle(state, generation: generation) }
        }
        browser.browseResultsChangedHandler = { @Sendable [weak self] results, changes in
            let mapped = results.map { BonjourResult($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let added = changes.count(where: { if case .added = $0 { true } else { false } })
            let removed = changes.count(where: { if case .removed = $0 { true } else { false } })
            Task { @MainActor in self?.update(mapped, added: added, removed: removed, generation: generation) }
        }
        self.browser = browser
        browsedType = type
        isBrowsing = true
        state = "Setup"
        results = []
        let declared = BonjourServiceType.declaredTypes().contains(type)
        message = "Browsing \(type) in local. and on peer-to-peer Wi-Fi…" + (declared ? "" : "\n\(type) is not declared in NSBonjourServices; iOS refuses undeclared types with NoAuth (-65555).")
        browser.start(queue: queue)
        #else
        message = "Network.framework is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(Network)
        guard let browser else { return }
        generation += 1
        browser.stateUpdateHandler = nil
        browser.browseResultsChangedHandler = nil
        browser.cancel()
        self.browser = nil
        isBrowsing = false
        state = "Stopped"
        #endif
    }

    #if canImport(Network)
    private func handle(_ newState: NWBrowser.State, generation: Int) {
        guard generation == self.generation else { return }
        switch newState {
        case .setup:
            state = "Setup"
        case .ready:
            state = "Ready"
        case .waiting(let error):
            state = "Waiting"
            sawLocalNetworkDenial = sawLocalNetworkDenial || NetworkErrorExplainer.isLocalNetworkDenial(error)
            message = "waiting: \(NetworkErrorExplainer.explain(error))"
        case .failed(let error):
            state = "Failed"
            sawLocalNetworkDenial = sawLocalNetworkDenial || NetworkErrorExplainer.isLocalNetworkDenial(error)
            message = "failed: \(NetworkErrorExplainer.explain(error))"
            stop()
            state = "Failed"
        case .cancelled:
            state = "Stopped"
        @unknown default:
            state = "Unknown"
        }
    }

    private func update(_ results: [BonjourResult], added: Int, removed: Int, generation: Int) {
        guard generation == self.generation else { return }
        self.results = results
        message = "\(results.count) service\(results.count == 1 ? "" : "s") of type \(browsedType ?? "?") · last change: +\(added) −\(removed)"
    }
    #endif
}
