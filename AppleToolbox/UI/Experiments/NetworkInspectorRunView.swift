import SwiftUI
#if canImport(Network)
import Network
#endif

extension NetworkClientService: StoppableExperiment {}
extension NetworkListenerService: StoppableExperiment { var isActive: Bool { isRunning } }
extension BonjourBrowserService: StoppableExperiment { var isActive: Bool { isBrowsing } }

/// Network Inspector (spec §11, §40): path monitor, NWConnection client, NWListener echo server and NWBrowser.
struct NetworkInspectorRunView: View {
    @StateObject private var path = NetworkExperimentService()
    @StateObject private var client = NetworkClientService()
    @StateObject private var listener = NetworkListenerService()
    @StateObject private var browser = BonjourBrowserService()

    var body: some View {
        Button(path.isMonitoring ? "Stop Path Monitor" : "Start Path Monitor") { path.isMonitoring ? path.stop() : path.start() }
            .buttonStyle(.borderedProminent)
            .experimentSession(path)
        NetworkPathSection(path: path)
        NetworkClientSection(client: client)
        NetworkListenerSection(listener: listener, client: client)
        BonjourBrowserSection(browser: browser, client: client)
        LocalNetworkPrivacySection(client: client, listener: listener, browser: browser)
    }
}

private struct NetworkPathSection: View {
    @ObservedObject var path: NetworkExperimentService

    var body: some View {
        Section("Path · NWPathMonitor") {
            if let snapshot = path.snapshot {
                LabeledContent("Status", value: snapshot.status)
                if let reason = snapshot.unsatisfiedReason { LabeledContent("Unsatisfied reason", value: reason) }
                LabeledContent("Primary interface", value: snapshot.primaryInterface)
                LabeledContent("Expensive", value: snapshot.isExpensive ? "Yes (cellular or hotspot)" : "No")
                LabeledContent("Constrained", value: snapshot.isConstrained ? "Yes (Low Data Mode)" : "No")
                LabeledContent("Ultra constrained", value: snapshot.isUltraConstrained ? "Yes" : "No")
                LabeledContent("Link quality", value: snapshot.linkQuality)
                LabeledContent("IPv4 · IPv6 · DNS", value: [snapshot.supportsIPv4, snapshot.supportsIPv6, snapshot.supportsDNS].map { $0 ? "Yes" : "No" }.joined(separator: " · "))
                LabeledContent("Gateways") {
                    Text(snapshot.gateways.isEmpty ? "None reported" : snapshot.gateways.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("DNS servers", value: "No public API")
                ForEach(snapshot.interfaces) { interface in
                    Label {
                        VStack(alignment: .leading) {
                            Text(interface.name)
                            Text("\(interface.type) · index \(interface.index)").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: Self.symbol(for: interface.type))
                    }
                }
                if !path.transitions.isEmpty {
                    OutputView(text: NetworkLogFormatter.text(path.transitions, limit: 8, placeholder: ""), isError: false)
                }
            } else {
                Text("Start the path monitor to see status, interfaces (in preference order), cost, Low Data Mode, gateways and every transition while it runs. The addresses of the DNS servers are not exposed by any public API; NWPath only reports whether DNS is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func symbol(for type: String) -> String {
        switch type {
        case "Wi-Fi": "wifi"
        case "Cellular": "antenna.radiowaves.left.and.right"
        case "Ethernet": "cable.connector"
        case "Loopback": "arrow.triangle.2.circlepath"
        default: "network"
        }
    }
}

private struct NetworkClientSection: View {
    @ObservedObject var client: NetworkClientService
    @State private var transport = NetworkTransport.tls
    @State private var host = "example.com"
    @State private var port = "443"
    @State private var message = ""
    @State private var lineEnding = LineEnding.crlf

    var body: some View {
        Section("Connection · NWConnection") {
            Picker("Transport", selection: $transport) {
                ForEach(NetworkTransport.allCases) { Text($0.title).tag($0) }
            }
            .disabled(client.isActive)
            .onChange(of: transport) { old, new in
                if port == String(old.defaultPort) { port = String(new.defaultPort) }
            }
            TextField("Host or IP address", text: $host)
                .networkFieldStyle(.host)
                .disabled(client.isActive)
            TextField("Port", text: $port)
                .networkFieldStyle(.number)
                .disabled(client.isActive)
            Button(client.isActive ? "Cancel Connection" : "Connect") {
                client.isActive ? client.stop() : client.connect(host: host, port: port, transport: transport)
            }
            .buttonStyle(.borderedProminent)
            .experimentSession(client)
            LabeledContent("State", value: client.state)
            ForEach(client.details) { row in
                LabeledContent(row.title) {
                    Text(row.value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
                }
            }
            TextField("Message", text: $message)
                .networkFieldStyle(.text)
            Picker("Line ending", selection: $lineEnding) {
                ForEach(LineEnding.allCases) { Text($0.title).tag($0) }
            }
            HStack {
                Button("Send") { client.send(message, lineEnding: lineEnding) }
                    .buttonStyle(.bordered)
                    .disabled(!client.isReady)
                if client.httpHost != nil && client.transport != .udp {
                    Button("Send HTTP HEAD", action: client.sendHTTPHead)
                        .buttonStyle(.bordered)
                        .disabled(!client.isReady)
                }
                Spacer()
                Button("Clear Log", action: client.clearLog)
                    .buttonStyle(.borderless)
            }
            OutputView(text: NetworkLogFormatter.text(client.log, placeholder: "State changes, sent and received bytes and TLS details appear here. TLS shows the negotiated version, cipher suite, ALPN and the server's certificate chain once the connection is ready."),
                       isError: client.log.last?.kind == .error)
        }
    }
}

private struct NetworkListenerSection: View {
    @ObservedObject var listener: NetworkListenerService
    @ObservedObject var client: NetworkClientService

    var body: some View {
        Section("Echo listener · NWListener + Bonjour") {
            Button(listener.isRunning ? "Stop Listener" : "Start Echo Listener") { listener.isRunning ? listener.stop() : listener.start() }
                .buttonStyle(.borderedProminent)
                .experimentSession(listener)
            LabeledContent("State", value: listener.state)
            LabeledContent("TCP port", value: listener.port.map(String.init) ?? "—")
            LabeledContent("Bonjour service") {
                Text(listener.registeredService ?? "Not registered").font(.caption.monospaced()).multilineTextAlignment(.trailing)
            }
            LabeledContent("Clients", value: "\(listener.activeConnections) connected · \(listener.totalConnections) total")
            if let port = listener.port {
                Button("Connect the client to this listener") { client.connect(host: "127.0.0.1", port: String(port), transport: .tcp) }
                    .disabled(client.isActive)
            }
            Text("The listener accepts TCP clients on an automatic port and sends every received byte straight back. It advertises \(BonjourServiceType.echo.type) with this device's name, so a second device finds it with the browser below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            OutputView(text: NetworkLogFormatter.text(listener.log, placeholder: "Listener state, Bonjour registration and client traffic appear here."),
                       isError: listener.log.last?.kind == .error)
        }
    }
}

private struct BonjourBrowserSection: View {
    private static let otherTag = "other"

    @ObservedObject var browser: BonjourBrowserService
    @ObservedObject var client: NetworkClientService
    @State private var selection = BonjourServiceType.presets[0].type
    @State private var customType = "_example._tcp"

    private var serviceType: String { selection == Self.otherTag ? customType : selection }

    var body: some View {
        Section("Bonjour browser · NWBrowser") {
            Picker("Service type", selection: $selection) {
                ForEach(BonjourServiceType.presets) { Text("\($0.title) · \($0.type)").tag($0.type) }
                Text("Other…").tag(Self.otherTag)
            }
            .disabled(browser.isBrowsing)
            if selection == Self.otherTag {
                TextField("_service._tcp", text: $customType)
                    .networkFieldStyle(.host)
                    .disabled(browser.isBrowsing)
                if !BonjourServiceType.declaredTypes().contains(customType.trimmingCharacters(in: .whitespaces)) {
                    Text("Not declared in NSBonjourServices. iOS and iPadOS refuse the browse with NoAuth (-65555); try it to see the real error.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Button(browser.isBrowsing ? "Stop Browsing" : "Browse") { browser.isBrowsing ? browser.stop() : browser.start(type: serviceType) }
                .buttonStyle(.borderedProminent)
                .experimentSession(browser)
            LabeledContent("State", value: browser.state)
            ForEach(browser.results) { result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.name).font(.headline)
                        Spacer()
                        #if canImport(Network)
                        if result.type.hasSuffix("._tcp") {
                            Button("Connect") { client.connect(to: result.endpoint, label: result.name) }
                                .buttonStyle(.bordered)
                                .disabled(client.isActive)
                        }
                        #endif
                    }
                    Text("\(result.type) · \(result.domain)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    if !result.interfaces.isEmpty {
                        Text(result.interfaces.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                    if !result.txtRecord.isEmpty {
                        Text(result.txtRecord.joined(separator: "  ")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            OutputView(text: browser.message, isError: browser.state == "Failed" || browser.state == "Waiting")
            Text("Apps can only browse service types they list in NSBonjourServices. Apple Toolbox declares every preset above; “Other…” shows what happens with an undeclared type. Connect opens the Bonjour endpoint with the NWConnection client above, which resolves the service itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LocalNetworkPrivacySection: View {
    @ObservedObject var client: NetworkClientService
    @ObservedObject var listener: NetworkListenerService
    @ObservedObject var browser: BonjourBrowserService

    private var observation: String {
        if client.sawLocalNetworkDenial || listener.sawLocalNetworkDenial || browser.sawLocalNetworkDenial {
            return "Denied (PolicyDenied reported)"
        }
        if !browser.results.isEmpty || listener.registeredService != nil {
            return "Allowed (Bonjour operations succeed)"
        }
        return "Not observed yet"
    }

    var body: some View {
        Section("Local network privacy") {
            LabeledContent("Observed access", value: observation)
            Text("iOS, iPadOS and macOS 15 or later ask once, the first time the app advertises, browses or connects to a device on the local network, using NSLocalNetworkUsageDescription. No API reports the decision: a denial shows up as DNS-SD error -65570 (PolicyDenied) on Bonjour operations, as the path reason “local network denied”, or as a connection to a local address that stays in waiting. Change it in Settings › Privacy & Security › Local Network. Internet hosts are not affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum NetworkFieldKind { case host, number, text }

extension View {
    /// Plain, uncorrected monospaced input for hosts, ports, service types and protocol payloads.
    @ViewBuilder
    func networkFieldStyle(_ kind: NetworkFieldKind) -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(kind == .number ? .numberPad : kind == .host ? .URL : .asciiCapable)
            .font(.body.monospaced())
        #elseif os(tvOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
            .font(.body.monospaced())
        #endif
    }
}
