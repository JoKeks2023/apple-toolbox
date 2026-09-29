import SwiftUI

// Compact watch run views for Core Bluetooth and Nearby Interaction.

struct WatchBluetoothView: View {
    @StateObject private var bluetooth = BluetoothExperimentService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if bluetooth.isConnected {
                WatchBluetoothConnectionSection(bluetooth: bluetooth)
            } else {
                Button(bluetooth.isScanning ? "Stop Scan" : "Scan", systemImage: bluetooth.isScanning ? "stop.fill" : "antenna.radiowaves.left.and.right") {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.start()
                }
                Section("Peripherals · \(bluetooth.peripherals.count)") {
                    ForEach(bluetooth.peripherals.sorted { $0.rssi > $1.rssi }) { peripheral in
                        Button { bluetooth.connect(to: peripheral.id) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(peripheral.name).lineLimit(1)
                                Text("\(peripheral.rssi) dBm" + (peripheral.isConnectable == false ? " · not connectable" : ""))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(peripheral.isConnectable == false)
                    }
                }
            }
            WatchOutput(text: bluetooth.output, isError: bluetooth.output.localizedCaseInsensitiveContains("not ready") || bluetooth.output.localizedCaseInsensitiveContains("error"))
        }
        .navigationTitle("Bluetooth")
        .onDisappear { bluetooth.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { bluetooth.stop() }
        }
    }
}

private struct WatchBluetoothConnectionSection: View {
    @ObservedObject var bluetooth: BluetoothExperimentService

    var body: some View {
        Section(bluetooth.connectedName) {
            LabeledContent("State", value: bluetooth.connectionState.rawValue)
            LabeledContent("RSSI", value: bluetooth.rssi.map { "\($0) dBm" } ?? "—")
            Button("Read RSSI", systemImage: "cellularbars", action: bluetooth.readRSSI)
            Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: bluetooth.disconnect)
        }
        ForEach(bluetooth.services) { service in
            Section(service.name ?? GATTNames.shortForm(service.uuid)) {
                ForEach(service.characteristics) { characteristic in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(characteristic.name ?? GATTNames.shortForm(characteristic.uuid)).font(.caption.weight(.semibold))
                        Text(characteristic.properties.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                        Text(GATTFormatting.summary(characteristic.value)).font(.caption2.monospaced())
                        HStack {
                            if characteristic.canRead {
                                Button("Read") { bluetooth.read(characteristic.id) }
                            }
                            if characteristic.canSubscribe {
                                Button(characteristic.isNotifying ? "Unsubscribe" : "Notify") {
                                    bluetooth.setNotifications(!characteristic.isNotifying, for: characteristic.id)
                                }
                            }
                        }
                        .font(.caption2)
                    }
                }
            }
        }
    }
}

struct WatchNearbyView: View {
    @StateObject private var nearby = NearbyExperimentService()
    @ObservedObject private var link = ContinuityExperimentService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Button(nearby.isRunning ? "Stop" : "Start", systemImage: nearby.isRunning ? "stop.fill" : "wave.3.right") {
                nearby.isRunning ? nearby.stop() : nearby.start()
            }
            .disabled(!nearby.capabilities.preciseDistance && !nearby.isRunning)
            if nearby.isRunning, nearby.reading == nil {
                Button("Send Token Again", systemImage: "arrow.clockwise", action: nearby.retryTokenExchange)
            }
            Section("Live") {
                Text(nearby.reading?.distance.map(NearbyGeometry.meters) ?? "—")
                    .font(.title2.monospacedDigit().weight(.semibold))
                LabeledContent("Session", value: nearby.phase)
                LabeledContent("Peer", value: nearby.peerName ?? "—")
                LabeledContent("iPhone reachable", value: link.isReachable ? "Yes" : "No")
                LabeledContent("Direction", value: nearby.reading?.direction.map { NearbyGeometry.degrees(NearbyGeometry.azimuth($0)) } ?? "Not reported")
            }
            Section {
                LabeledContent("Precise distance", value: nearby.capabilities.preciseDistance ? "Yes" : "No")
                LabeledContent("Direction", value: nearby.capabilities.direction ? "Yes" : "No")
                LabeledContent("iPhone precise distance", value: nearby.peerCapabilities.map { $0.preciseDistance ? "Yes" : "No" } ?? "—")
            } header: {
                Text("NIDeviceCapability")
            } footer: {
                Text("Apple Watch Series 6 or later ranges with its paired iPhone. watchOS has no MultipeerConnectivity, so the discovery tokens travel over WatchConnectivity: keep Apple Toolbox open on the iPhone.")
            }
            WatchOutput(text: nearby.output, isError: nearby.output.localizedCaseInsensitiveContains("error") || nearby.output.localizedCaseInsensitiveContains("failed"))
        }
        .navigationTitle("Nearby")
        .onDisappear { nearby.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, nearby.isRunning { nearby.stop() }
        }
    }
}
