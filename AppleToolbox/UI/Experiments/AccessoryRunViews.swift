import SwiftUI
#if canImport(CoreAudioKit) && (os(iOS) || os(macOS))
import CoreAudioKit
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AccessorySetupKitRunView: View {
    @StateObject private var accessories = AccessorySetupKitExperimentService()

    var body: some View {
        HStack {
            Button(accessories.isSessionActive ? "Session Active" : "Activate Session", systemImage: "bolt.horizontal.circle", action: accessories.activate)
                .buttonStyle(.borderedProminent)
                .disabled(accessories.isActive)
            Button("Show Accessory Picker", systemImage: "plus.circle", action: accessories.showPicker)
                .buttonStyle(.bordered)
                .disabled(!accessories.isSessionActive || !accessories.missingEntries.isEmpty)
        }
        .experimentSession(accessories)
        Section("Picker item") {
            LabeledContent("Name", value: "Apple Toolbox Peripheral")
            LabeledContent("Service UUID") { Text(ToolboxGATTProfile.serviceUUID).font(.caption.monospaced()) }
            LabeledContent("Name substring", value: ToolboxGATTProfile.localName)
            Text("Matches a second iPhone, iPad or Mac running Bluetooth Peripheral Mode, the same way Apple's AccessorySetupKit sample pairs with a simulated accessory app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Info.plist declaration") {
            LabeledContent("NSAccessorySetupKitSupports", value: accessories.declaration.supports.isEmpty ? "Not declared" : accessories.declaration.supports.joined(separator: ", "))
            if accessories.missingEntries.isEmpty {
                Label("The picker item is declared.", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                ForEach(accessories.missingEntries, id: \.self) { entry in
                    Label(entry, systemImage: "xmark.circle").font(.caption.monospaced()).foregroundStyle(.orange)
                }
                Text("Apple documents that AccessorySetupKit terminates an app whose picker looks for Bluetooth identifiers its Info.plist does not declare, so the picker stays disabled. This build leaves the Bluetooth declaration out on purpose: according to Apple, once an app declares it, Core Bluetooth only reaches accessories set up through AccessorySetupKit, which would limit the Core Bluetooth scanner and GATT explorer to those accessories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Authorized accessories (\(accessories.accessories.count))") {
            if accessories.accessories.isEmpty {
                Text(accessories.isSessionActive ? "No accessory is authorized for Apple Toolbox." : "Activate the session to read ASAccessorySession.accessories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(accessories.accessories) { accessory in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accessory.displayName).font(.headline)
                        Text(accessory.state).font(.caption)
                        if let identifier = accessory.bluetoothIdentifier {
                            Text(identifier.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { accessories.remove(accessory.id) }
                        .buttonStyle(.bordered)
                }
            }
        }
        AccessoryEventsSection(title: "Session events", entries: accessories.events)
        OutputView(text: accessories.output, isError: accessories.output.localizedCaseInsensitiveContains("error") || accessories.output.localizedCaseInsensitiveContains("not shown") || accessories.output.localizedCaseInsensitiveContains("only available"))
    }
}

struct ExternalAccessoryRunView: View {
    @StateObject private var external = ExternalAccessoryExperimentService()

    var body: some View {
        HStack {
            if external.isMonitoring {
                Button("Stop Listening", systemImage: "stop.circle", action: external.stop).buttonStyle(.borderedProminent)
            } else {
                Button("Listen for Accessories", systemImage: "cable.connector", action: external.start).buttonStyle(.borderedProminent)
            }
            Button("Refresh", systemImage: "arrow.clockwise", action: external.refresh).buttonStyle(.bordered)
        }
        .experimentSession(external)
        Section("Connected accessories (\(external.accessories.count))") {
            if external.accessories.isEmpty {
                Text("EAAccessoryManager.connectedAccessories is empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(external.accessories) { accessory in
                VStack(alignment: .leading, spacing: 3) {
                    Text(accessory.name).font(.headline)
                    Text("\(accessory.manufacturer) · model \(accessory.modelNumber)").font(.caption)
                    Text("Serial \(accessory.serialNumber) · firmware \(accessory.firmwareRevision) · hardware \(accessory.hardwareRevision)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(accessory.protocols.isEmpty ? "No protocols" : "Protocols: \(accessory.protocols.joined(separator: ", "))")
                        .font(.caption2.monospaced())
                }
            }
        }
        Section("Protocol boundary") {
            LabeledContent("UISupportedExternalAccessoryProtocols", value: external.declaredProtocols.isEmpty ? "None declared" : external.declaredProtocols.joined(separator: ", "))
            Text("External Accessory talks to MFi accessories over Lightning, USB-C or Bluetooth using protocols their maker defines. An app can open an EASession only for protocols it lists in UISupportedExternalAccessoryProtocols, and iOS makes an accessory available to an app for those protocols. Apple Toolbox declares none, because each protocol belongs to an accessory maker who authorizes apps through the MFi Program. Bluetooth LE devices appear in Core Bluetooth instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        AccessoryEventsSection(title: "Connection events", entries: external.events)
        OutputView(text: external.output, isError: external.output.localizedCaseInsensitiveContains("not available"))
    }
}

struct BluetoothMIDIRunView: View {
    @StateObject private var midi = MIDIExperimentService()
    @State private var showsBluetoothPairing = false
    #if canImport(CoreAudioKit) && os(macOS)
    @State private var pairingWindow: CABTLEMIDIWindowController?
    #endif

    var body: some View {
        HStack {
            if midi.isListening {
                Button("Stop Listening", systemImage: "stop.circle", action: midi.stop).buttonStyle(.borderedProminent)
            } else {
                Button("Listen to MIDI Sources", systemImage: "pianokeys", action: midi.start).buttonStyle(.borderedProminent)
            }
            Button("Refresh", systemImage: "arrow.clockwise", action: midi.refreshEndpoints).buttonStyle(.bordered)
        }
        .experimentSession(midi)
        pairingButton
        MIDIEndpointsSection(title: "Sources", endpoints: midi.sources)
        MIDIEndpointsSection(title: "Destinations", endpoints: midi.destinations)
        Section("Incoming MIDI (\(midi.events.count))") {
            if midi.events.isEmpty {
                Text(midi.isListening ? "Waiting for MIDI messages…" : "Start listening, then play a connected MIDI device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(midi.events.suffix(40).reversed()) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(event.message).font(.caption.weight(.semibold))
                        Spacer()
                        Text(event.date, format: .dateTime.hour().minute().second()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text("\(event.source) · UMP \(event.raw)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            if !midi.events.isEmpty {
                Button("Clear", systemImage: "trash", action: midi.clearEvents)
            }
        }
        OutputView(text: midi.output, isError: midi.output.localizedCaseInsensitiveContains("failed") || midi.output.localizedCaseInsensitiveContains("not available"))
    }

    @ViewBuilder private var pairingButton: some View {
        #if canImport(CoreAudioKit) && os(iOS)
        Button("Pair Bluetooth MIDI Device", systemImage: "dot.radiowaves.left.and.right") { showsBluetoothPairing = true }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showsBluetoothPairing) {
                BluetoothMIDICentralView { showsBluetoothPairing = false }
            }
        Text("CABTMIDICentralViewController scans for Bluetooth LE MIDI devices and connects them system-wide; they then appear as sources and destinations below.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #elseif canImport(CoreAudioKit) && os(macOS)
        Button("Pair Bluetooth MIDI Device", systemImage: "dot.radiowaves.left.and.right") {
            let controller = pairingWindow ?? CABTLEMIDIWindowController()
            pairingWindow = controller
            controller.showWindow(nil)
        }
        .buttonStyle(.bordered)
        Text("CABTLEMIDIWindowController lists Bluetooth LE MIDI devices and connects them system-wide; they then appear as sources and destinations below.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}

private struct MIDIEndpointsSection: View {
    let title: String
    let endpoints: [MIDIEndpointInfo]

    var body: some View {
        Section("\(title) (\(endpoints.count))") {
            if endpoints.isEmpty {
                Text("No MIDI \(title.lowercased()) found.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(endpoints) { endpoint in
                HStack {
                    Label(endpoint.name, systemImage: endpoint.isBluetooth ? "dot.radiowaves.left.and.right" : "pianokeys")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let manufacturer = endpoint.manufacturer { Text(manufacturer).font(.caption2) }
                        if let driver = endpoint.driver { Text(driver).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                        if endpoint.isOffline { Text("Offline").font(.caption2).foregroundStyle(.orange) }
                    }
                }
            }
        }
    }
}

private struct AccessoryEventsSection: View {
    let title: String
    let entries: [AccessoryEventEntry]

    var body: some View {
        if !entries.isEmpty {
            Section("\(title) (\(entries.count))") {
                ForEach(entries.suffix(40).reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(entry.isError ? .red : .primary)
                            Spacer()
                            Text(entry.date, format: .dateTime.hour().minute().second()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(entry.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#if canImport(CoreAudioKit) && os(iOS)
/// Apple's Bluetooth LE MIDI pairing UI in a navigation controller with a Done button.
private struct BluetoothMIDICentralView: UIViewControllerRepresentable {
    let done: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let central = CABTMIDICentralViewController()
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in done() })
        return UINavigationController(rootViewController: central)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
#endif

// Lifecycle conformances live next to the run views: the services also compile for watchOS, where the protocol does not exist.
extension AccessorySetupKitExperimentService: StoppableExperiment {}
extension ExternalAccessoryExperimentService: StoppableExperiment { var isActive: Bool { isMonitoring } }
extension MIDIExperimentService: StoppableExperiment { var isActive: Bool { isListening } }
