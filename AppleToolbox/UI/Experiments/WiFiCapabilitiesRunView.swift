import SwiftUI

extension WiFiCapabilityService: StoppableExperiment {}

/// Wi-Fi and network capabilities (spec §11–12): current network, hotspot configuration, local network probe
/// and the entitlement boundaries of Multicast, Personal VPN, Network Extensions, Multipath and 5G slicing.
struct WiFiCapabilitiesRunView: View {
    @StateObject private var service = WiFiCapabilityService()

    var body: some View {
        CurrentWiFiSection(service: service)
        #if os(iOS)
        HotspotSection(service: service)
        #endif
        LocalNetworkProbeSection(service: service)
        CapabilityBoundarySection(service: service)
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
