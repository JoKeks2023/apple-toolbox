import SwiftUI

struct CoreBluetoothRunView: View {
    @StateObject private var bluetooth = BluetoothExperimentService()

    var body: some View {
        HStack {
            Button(bluetooth.isScanning ? "Stop Bluetooth Scan" : "Start Bluetooth Scan") { bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.start() }.buttonStyle(.borderedProminent)
            Button("Clear", action: bluetooth.clearResults).buttonStyle(.bordered)
        }
        .experimentSession(bluetooth)
        if bluetooth.isConnected {
            GATTConnectionSection(bluetooth: bluetooth)
            GATTServicesSection(bluetooth: bluetooth)
        }
        if !bluetooth.log.isEmpty {
            GATTLogSection(entries: bluetooth.log, clear: bluetooth.clearLog)
        }
        BluetoothResultsView(peripherals: bluetooth.peripherals, connectedID: bluetooth.connectedPeripheralID, connect: bluetooth.connect(to:))
        OutputView(text: bluetooth.output, isError: bluetooth.output.localizedCaseInsensitiveContains("not available") || bluetooth.output.localizedCaseInsensitiveContains("unauthorized") || bluetooth.output.localizedCaseInsensitiveContains("could not"))
    }
}

private struct GATTConnectionSection: View {
    @ObservedObject var bluetooth: BluetoothExperimentService

    var body: some View {
        Section("GATT explorer") {
            LabeledContent("Peripheral", value: bluetooth.connectedName)
            if let id = bluetooth.connectedPeripheralID {
                LabeledContent("Identifier") { Text(id.uuidString).font(.caption.monospaced()) }
            }
            LabeledContent("State", value: bluetooth.connectionState.rawValue)
            LabeledContent("RSSI", value: bluetooth.rssi.map { "\($0) dBm" } ?? "—")
            if let limits = bluetooth.writeLimits {
                LabeledContent("Max write (with response)", value: "\(limits.withResponse) B")
                LabeledContent("Max write (without response)", value: "\(limits.withoutResponse) B · ATT MTU \(limits.withoutResponse + 3)")
            }
            HStack {
                Button("Read RSSI", systemImage: "antenna.radiowaves.left.and.right", action: bluetooth.readRSSI)
                    .disabled(bluetooth.connectionState == .connecting)
                Button("Rediscover", systemImage: "arrow.clockwise", action: bluetooth.rediscover)
                    .disabled(bluetooth.connectionState != .connected)
                Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: bluetooth.disconnect)
                    .disabled(bluetooth.connectionState == .disconnecting)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct GATTServicesSection: View {
    @ObservedObject var bluetooth: BluetoothExperimentService

    var body: some View {
        Section("Services (\(bluetooth.services.count))") {
            if bluetooth.services.isEmpty {
                Text(bluetooth.connectionState == .connecting ? "Waiting for the connection…" : "No services discovered yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(bluetooth.services) { service in
                GATTDisclosure {
                    if service.characteristics.isEmpty {
                        Text("No characteristics").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(service.characteristics) { characteristic in
                        GATTCharacteristicRow(characteristic: characteristic, bluetooth: bluetooth)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.name ?? "Custom service").font(.headline)
                        Text(service.uuid).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("\(service.isPrimary ? "Primary" : "Secondary") · \(service.characteristics.count) characteristic\(service.characteristics.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct GATTCharacteristicRow: View {
    let characteristic: GATTCharacteristicNode
    @ObservedObject var bluetooth: BluetoothExperimentService
    @State private var input = ""
    @State private var format: GATTValueFormat = .hex
    @State private var writeKind: GATTWriteKind = .withResponse
    @State private var inputError: String?

    private var writeKinds: [GATTWriteKind] {
        GATTWriteKind.allCases.filter { $0 == .withResponse ? characteristic.canWrite : characteristic.canWriteWithoutResponse }
    }

    var body: some View {
        GATTDisclosure {
            VStack(alignment: .leading, spacing: 4) {
                Text("Value").font(.caption.weight(.semibold))
                Text(characteristic.value.map(GATTFormatting.hex) ?? "Not read yet")
                    .font(.caption.monospaced())
                if let value = characteristic.value, let text = GATTFormatting.utf8(value) {
                    Text("UTF-8: “\(text)”").font(.caption)
                }
                if let value = characteristic.value {
                    Text("\(value.count) B").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(characteristic.descriptors) { descriptor in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.name ?? descriptor.uuid).font(.caption.weight(.semibold))
                        if descriptor.name != nil { Text(descriptor.uuid).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                        Text(descriptor.value).font(.caption.monospaced())
                    }
                    Spacer()
                    Button("Read") { bluetooth.readDescriptor(descriptor.id) }
                        .buttonStyle(.bordered)
                }
            }
            if characteristic.canRead || characteristic.canSubscribe {
                HStack {
                    if characteristic.canRead {
                        Button("Read", systemImage: "arrow.down.circle") { bluetooth.read(characteristic.id) }
                            .buttonStyle(.bordered)
                    }
                    if characteristic.canSubscribe {
                        Toggle("Notifications", isOn: Binding(get: { characteristic.isNotifying },
                                                              set: { bluetooth.setNotifications($0, for: characteristic.id) }))
                    }
                }
            }
            if !writeKinds.isEmpty {
                writeEditor
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(characteristic.name ?? "Custom characteristic").font(.subheadline.weight(.semibold))
                Text(characteristic.uuid).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(characteristic.properties.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                if characteristic.isNotifying {
                    Label("Subscribed", systemImage: "bell.badge").font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .onAppear { if let first = writeKinds.first { writeKind = first } }
    }

    @ViewBuilder private var writeEditor: some View {
        Picker("Input", selection: $format) {
            ForEach(GATTValueFormat.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("Write type", selection: $writeKind) {
            ForEach(writeKinds) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.menu)
        TextField(format == .hex ? "Bytes, e.g. 01 A0 FF" : "Text to send", text: $input)
            .font(.body.monospaced())
            .autocorrectionDisabled()
        if let inputError {
            Text(inputError).font(.caption).foregroundStyle(.red)
        }
        Button("Write", systemImage: "arrow.up.circle") {
            do {
                let data = try GATTFormatting.encode(input, as: format)
                inputError = nil
                bluetooth.write(data, to: characteristic.id, kind: writeKind)
            } catch {
                inputError = error.localizedDescription
            }
        }
        .buttonStyle(.bordered)
        .disabled(bluetooth.connectionState != .connected)
    }
}

private struct GATTLogSection: View {
    let entries: [GATTLogEntry]
    let clear: @MainActor () -> Void

    var body: some View {
        Section("Live log (\(entries.count))") {
            ForEach(entries.suffix(40).reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.kind.rawValue.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color(for: entry.kind))
                        Text(entry.title).font(.caption.weight(.semibold))
                        Spacer()
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            Button("Clear Log", systemImage: "trash", action: clear)
        }
    }

    private func color(for kind: GATTLogEntry.Kind) -> Color {
        switch kind {
        case .info: .secondary
        case .read: .blue
        case .write: .orange
        case .notification: .green
        case .error: .red
        }
    }
}

private struct BluetoothResultsView: View {
    let peripherals: [BluetoothPeripheralResult]
    let connectedID: UUID?
    let connect: @MainActor (UUID) -> Void

    var body: some View {
        Section("Discovered peripherals (\(peripherals.count))") {
            if peripherals.isEmpty {
                Label("No peripherals discovered yet", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text("Start a scan and keep this screen open. Results update live as advertisements arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(peripherals) { peripheral in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(peripheral.name, systemImage: "dot.radiowaves.left.and.right")
                                .font(.headline)
                            Spacer()
                            Text("\(peripheral.rssi) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(peripheral.rssi >= -60 ? .green : .secondary)
                        }
                        Text(peripheral.id.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(peripheral.advertisedServices.isEmpty ? "No advertised services" : "Services: \(peripheral.advertisedServices.joined(separator: ", "))")
                            Spacer()
                            if peripheral.manufacturerDataBytes > 0 {
                                Text("Manufacturer: \(peripheral.manufacturerDataBytes) B")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            if peripheral.isConnectable == false {
                                Text("Advertises as not connectable").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if peripheral.id == connectedID {
                                Label("Selected in GATT explorer", systemImage: "link").font(.caption).foregroundStyle(.green)
                            } else {
                                Button("Connect", systemImage: "link") { connect(peripheral.id) }
                                    .buttonStyle(.bordered)
                                    .disabled(peripheral.isConnectable == false)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct BluetoothPeripheralModeRunView: View {
    @StateObject private var peripheral = BluetoothPeripheralModeService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if peripheral.isRunning {
                Button("Stop Advertising", systemImage: "stop.circle", action: peripheral.stop)
            } else {
                Button("Start Advertising", systemImage: "dot.radiowaves.left.and.right", action: peripheral.start)
            }
        }
        .buttonStyle(.borderedProminent)
        .experimentSession(peripheral)
        .onChange(of: scenePhase) { _, phase in peripheral.noteScenePhase(isBackground: phase == .background) }
        LabeledContent("Bluetooth", value: peripheral.managerState)
        LabeledContent("Advertising", value: peripheral.isAdvertising ? "“\(ToolboxGATTProfile.localName)” + service UUID" : "No")
        LabeledContent("Subscribed centrals", value: "\(peripheral.subscribers.count)")
        if let limit = peripheral.notificationLimit {
            LabeledContent("Max notification size", value: "\(limit) B")
        }
        LabeledContent("Feed counter", value: "\(peripheral.counter)")
        LabeledContent("Last write to Inbox") {
            Text(GATTFormatting.summary(peripheral.lastWrite)).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }
        Section("Send a notification on Feed") {
            Picker("Payload", selection: $peripheral.source) {
                ForEach(ToolboxGATTProfile.NotificationSource.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            if peripheral.source == .text {
                TextField("Notification text", text: $peripheral.customText)
            }
            Button("Send Notification", systemImage: "bell", action: peripheral.sendNotification)
                .buttonStyle(.bordered)
                .disabled(!peripheral.isAdvertising)
            Toggle("Send every second while subscribed", isOn: Binding(get: { peripheral.isAutoSending }, set: { peripheral.setAutoSend($0) }))
                .disabled(!peripheral.isRunning)
        }
        ToolboxProfileSection()
        if !peripheral.log.isEmpty {
            GATTLogSection(entries: peripheral.log, clear: peripheral.clearLog)
        }
        Section("Background limits") {
            Text("While Apple Toolbox is in the foreground it advertises the local name and the service UUID. This build declares no bluetooth-peripheral background mode, so iOS suspends the app in the background and advertising stops. Apps that declare the mode keep advertising, but iOS drops the local name and moves service UUIDs into an overflow area that only iOS devices explicitly scanning for that UUID can see, at a reduced advertising rate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        OutputView(text: peripheral.output, isError: peripheral.output.localizedCaseInsensitiveContains("could not") || peripheral.output.localizedCaseInsensitiveContains("not available") || peripheral.output.localizedCaseInsensitiveContains("unauthorized"))
    }
}

private struct ToolboxProfileSection: View {
    var body: some View {
        Section("Published GATT profile") {
            LabeledContent("Service") { Text(ToolboxGATTProfile.serviceUUID).font(.caption.monospaced()) }
            row("Info", uuid: ToolboxGATTProfile.infoUUID, properties: "Read", detail: "Device summary, generated for every read request")
            row("Inbox", uuid: ToolboxGATTProfile.inboxUUID, properties: "Write · Write without response", detail: "Stores up to 512 B; shown above as Last write")
            row("Feed", uuid: ToolboxGATTProfile.feedUUID, properties: "Notify · Read", detail: "Counter or your text, sent to subscribed centrals")
        }
    }

    private func row(_ name: String, uuid: String, properties: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(uuid).font(.caption2.monospaced()).foregroundStyle(.secondary)
            Text("\(properties) · \(detail)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Collapsible group; tvOS has no DisclosureGroup, so it shows the content expanded there.
struct GATTDisclosure<Content: View, Header: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Header

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 8) {
            label()
            content()
        }
        #else
        DisclosureGroup(content: content, label: label)
        #endif
    }
}

// Declared here rather than in ExperimentLifecycle.swift so the Bluetooth experiments stay in their own files.
extension BluetoothPeripheralModeService: StoppableExperiment { var isActive: Bool { isRunning } }
