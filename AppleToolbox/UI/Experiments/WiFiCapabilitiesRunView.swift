import SwiftUI

extension WiFiCapabilityService: StoppableExperiment {}

/// Wi-Fi and network capabilities (spec §11–12): current network, hotspot configuration, local network probe,
/// the entitlement boundaries of Multicast, Personal VPN, Network Extensions, Multipath and 5G slicing, and on iOS
/// the bundled packet tunnel and a Personal VPN (IKEv2) configuration.
struct WiFiCapabilitiesRunView: View {
    @StateObject private var service = WiFiCapabilityService()

    var body: some View {
        CurrentWiFiSection(service: service)
        #if os(iOS)
        HotspotSection(service: service)
        #endif
        LocalNetworkProbeSection(service: service)
        CapabilityBoundarySection(service: service)
        #if os(iOS)
        PacketTunnelSection()
        PersonalVPNSection()
        #endif
    }
}

private struct CurrentWiFiSection: View {
    @ObservedObject var service: WiFiCapabilityService

    var body: some View {
        Section(sectionTitle) {
            LabeledContent("Location", value: service.location.title)
            if service.location == .notDetermined || service.location == .reducedAccuracy {
                Button(service.location == .notDetermined ? "Request Location Access" : "Request Precise Location Once", action: service.requestLocationAccess)
            }
            Button("Read Current Network", action: service.readCurrentNetwork)
                .buttonStyle(.borderedProminent)
            ForEach(service.currentNetwork) { row in
                LabeledContent(row.title) { Text(row.value).font(.body.monospaced()).multilineTextAlignment(.trailing) }
            }
            OutputView(text: service.wifiMessage, isError: service.wifiMessage.contains("nil") || service.wifiMessage.contains("failed"))
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sectionTitle: String {
        #if os(macOS)
        "Current Wi-Fi · CoreWLAN"
        #else
        "Current Wi-Fi · NEHotspotNetwork"
        #endif
    }

    private var footnote: String {
        #if os(macOS)
        "CWWiFiClient reports the interface, RSSI, noise, channel and security. Since macOS 14, SSID and BSSID stay hidden without location authorization. Apple's Wireless Diagnostics shows more, through private interfaces apps cannot use."
        #else
        "Third-party apps only get SSID, BSSID and security type, and only with the Access Wi-Fi Information entitlement plus precise location (or for a network the app configured, or with an active VPN or DNS settings configuration). Signal strength, channel and nearby networks are reserved for Apple's own tools and hotspot helper apps."
        #endif
    }
}

#if os(iOS)
private struct HotspotSection: View {
    @ObservedObject var service: WiFiCapabilityService
    @State private var ssid = ""
    @State private var passphrase = ""
    @State private var security = HotspotSecurity.personal
    @State private var joinOnce = true
    @State private var isConfirming = false

    var body: some View {
        Section("Hotspot · NEHotspotConfigurationManager") {
            LabeledContent("Entitlement") {
                Text(IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "hotspot"), key: "com.apple.developer.networking.HotspotConfiguration"))
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }
            TextField("Network name (SSID)", text: $ssid)
                .networkFieldStyle(.text)
            Picker("Security", selection: $security) {
                ForEach(HotspotSecurity.allCases) { Text($0.title).tag($0) }
            }
            if security.needsPassphrase {
                SecureField("Passphrase", text: $passphrase)
            }
            Toggle("Join once (forget when the app leaves the foreground)", isOn: $joinOnce)
            Button("Join Network…") {
                if let problem = HotspotInputValidator.problem(ssid: ssid.trimmingCharacters(in: .whitespacesAndNewlines), passphrase: passphrase, security: security) {
                    service.showHotspotProblem(problem)
                } else {
                    isConfirming = true
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(service.isApplyingHotspot)
            .confirmationDialog("Join “\(ssid)”?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Ask iOS to Join") { service.joinHotspot(ssid: ssid, passphrase: passphrase, security: security, joinOnce: joinOnce) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Apple Toolbox hands this configuration to NEHotspotConfigurationManager. iOS shows its own alert and only saves the network if you allow it there.")
            }
            OutputView(text: service.hotspotMessage, isError: service.hotspotMessage.hasPrefix("apply failed"))
            if service.configuredSSIDs.isEmpty {
                Text("No networks configured by Apple Toolbox. Apps can only list and remove the networks they added themselves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.configuredSSIDs, id: \.self) { configured in
                    HStack {
                        Label(configured, systemImage: "wifi")
                        Spacer()
                        Button("Remove", role: .destructive) { service.removeHotspot(configured) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .onAppear(perform: service.refreshConfiguredNetworks)
    }
}
#endif

#if os(iOS)
/// The bundled packet tunnel: install its configuration, start and stop it, send datagrams into the test range and
/// watch the provider's counters.
private struct PacketTunnelSection: View {
    @StateObject private var tunnel = PacketTunnelExperimentService()

    var body: some View {
        Section("Packet tunnel · NETunnelProviderManager") {
            LabeledContent("Extension", value: tunnel.providerBundleIdentifier ?? "Not embedded")
            LabeledContent("Status", value: tunnel.status)
            ForEach(tunnel.configuration) { row in LabeledContent(row.title, value: row.value) }
            HStack {
                Button("Load", action: tunnel.load)
                Button(tunnel.hasConfiguration ? "Save Again" : "Install", action: tunnel.install)
                if tunnel.hasConfiguration { Button("Remove", role: .destructive, action: tunnel.remove) }
            }
            .buttonStyle(.bordered)
            .disabled(tunnel.isWorking)
            Button(tunnel.isConnectingOrConnected ? "Stop Tunnel" : "Start Tunnel") {
                tunnel.isConnectingOrConnected ? tunnel.stopTunnel() : tunnel.start()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!tunnel.hasConfiguration || tunnel.isWorking)
            .experimentSession(tunnel)
            Picker("Test datagrams", selection: $tunnel.packetCount) {
                ForEach(PacketTunnelExperimentService.packetCounts, id: \.self) { Text("\($0)").tag($0) }
            }
            HStack {
                Button("Send to \(TunnelTestRange.testTarget)", action: tunnel.sendTestPackets)
                Button("Reset Counters", action: tunnel.resetStats)
            }
            .buttonStyle(.bordered)
            .disabled(!tunnel.isConnected)
            if let stats = tunnel.stats {
                OutputView(text: "Provider counters (handleAppMessage)\n" + stats.summary, isError: false)
            }
            OutputView(text: tunnel.output, isError: tunnel.isError)
            Text("The provider has no server: it claims only \(TunnelTestRange.cidr) (RFC 2544 benchmarking range) without DNS settings, so all other traffic keeps its normal route. It counts the packets that reach it and drops them. Leaving the experiment stops the tunnel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: tunnel.load)
    }
}

/// The built-in IKEv2 client. The form only saves what the person enters; connecting needs a real server.
private struct PersonalVPNSection: View {
    @StateObject private var vpn = PersonalVPNExperimentService()

    var body: some View {
        Section("Personal VPN · NEVPNManager (IKEv2)") {
            LabeledContent("Status", value: vpn.status)
            ForEach(vpn.savedSummary) { row in LabeledContent(row.title, value: row.value) }
            TextField("Server (host name or IP)", text: $vpn.form.server)
                .networkFieldStyle(.host)
            TextField("Remote ID", text: $vpn.form.remoteIdentifier)
                .networkFieldStyle(.host)
            TextField("Local ID (optional)", text: $vpn.form.localIdentifier)
                .networkFieldStyle(.text)
            Picker("Authentication", selection: $vpn.form.authentication) {
                ForEach(PersonalVPNAuthentication.allCases) { Text($0.title).tag($0) }
            }
            TextField(vpn.form.authentication == .usernamePassword ? "Username" : "Username (optional, EAP)", text: $vpn.form.username)
                .networkFieldStyle(.text)
            SecureField("Password", text: $vpn.form.password)
            if vpn.form.authentication == .sharedSecret {
                SecureField("Shared secret", text: $vpn.form.sharedSecret)
            }
            Picker("Encryption", selection: $vpn.form.encryption) {
                ForEach(PersonalVPNEncryption.allCases) { Text($0.title).tag($0) }
            }
            Picker("Diffie-Hellman group", selection: $vpn.form.diffieHellman) {
                ForEach(PersonalVPNDiffieHellman.allCases) { Text($0.title).tag($0) }
            }
            Picker("Dead peer detection", selection: $vpn.form.deadPeerDetection) {
                ForEach(PersonalVPNDeadPeerDetection.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Disconnect on sleep", isOn: $vpn.form.disconnectOnSleep)
            HStack {
                Button("Load", action: vpn.load)
                Button("Save Configuration", action: vpn.save)
                if vpn.hasConfiguration { Button("Remove", role: .destructive, action: vpn.remove) }
            }
            .buttonStyle(.bordered)
            .disabled(vpn.isWorking)
            Button(vpn.isConnectingOrConnected ? "Disconnect" : "Connect") {
                vpn.isConnectingOrConnected ? vpn.disconnect() : vpn.connect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vpn.hasConfiguration || vpn.isWorking)
            .experimentSession(vpn)
            OutputView(text: vpn.output, isError: vpn.isError)
            Text("Secrets go to the keychain; NEVPNManager only stores persistent references to them. There is no Apple Toolbox VPN server, so without your own IKEv2 server the connection fails and fetchLastDisconnectError reports why.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: vpn.load)
    }
}
#endif

private struct LocalNetworkProbeSection: View {
    @ObservedObject var service: WiFiCapabilityService

    var body: some View {
        Section("Local network permission") {
            LabeledContent("Probe result", value: service.probeOutcome.title)
            Button(service.probeOutcome == .running ? "Probing…" : "Probe Local Network Access", action: service.runLocalNetworkProbe)
                .buttonStyle(.borderedProminent)
                .disabled(service.probeOutcome == .running)
                .experimentSession(service)
            OutputView(text: NetworkLogFormatter.text(service.probeLog, placeholder: "There is no API that reads the local network permission. The probe advertises a uniquely named Bonjour service and browses for it: finding it proves access, DNS-SD error -65570 (PolicyDenied) proves a denial. The first run may show the system alert."),
                       isError: service.probeOutcome == .denied)
        }
    }
}

private struct CapabilityBoundarySection: View {
    @ObservedObject var service: WiFiCapabilityService

    var body: some View {
        Section("Capability boundaries") {
            ForEach(service.boundaries) { boundary in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(boundary.name).font(.headline)
                        Spacer()
                        Text(badge(for: boundary.isProvisioned))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(boundary.isProvisioned == true ? .green : .orange)
                    }
                    Text(boundary.gate).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(boundary.entitlement).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(boundary.boundary).font(.caption)
                    Text("Next step: \(boundary.requirement)").font(.caption).foregroundStyle(.secondary)
                    if let probe = boundary.probe, let title = boundary.probeTitle {
                        Button(service.runningProbe == probe ? "Running…" : title) { service.runProbe(probe, id: boundary.id) }
                            .buttonStyle(.bordered)
                            .disabled(service.runningProbe != nil)
                    }
                    if let result = service.probeResults[boundary.id] {
                        Text(result).font(.caption.monospaced()).textSelectionIfAvailable()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear(perform: service.refreshBoundaries)
    }

    private func badge(for provisioned: Bool?) -> String {
        switch provisioned {
        case true: "Provisioned"
        case false: "Not provisioned"
        case nil: "Unknown"
        }
    }
}

private extension View {
    @ViewBuilder
    func textSelectionIfAvailable() -> some View {
        #if os(tvOS)
        self
        #else
        self.textSelection(.enabled)
        #endif
    }
}
