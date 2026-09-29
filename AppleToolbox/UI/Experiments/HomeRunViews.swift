import SwiftUI
#if os(iOS) && canImport(VisionKit)
import VisionKit
import Vision
#endif

private enum HomeInspectorPane: String, CaseIterable, Identifiable {
    case accessories = "Accessories", scenes = "Scenes", automations = "Automations"
    var id: String { rawValue }
}

/// A write to a lock, door or alarm characteristic that waits for confirmation.
private struct HomePendingWrite: Identifiable {
    let id = UUID()
    let characteristicID: UUID
    let title: String
    let value: HomeWriteValue
    let valueText: String
}

struct HomeInspectorRunView: View {
    @StateObject private var inspector: HomeInspectorService
    @State private var pane = HomeInspectorPane.accessories
    @State private var pendingWrite: HomePendingWrite?
    @State private var pendingScene: HomeSceneInfo?

    init(experiment: ExperimentDescriptor) {
        _inspector = StateObject(wrappedValue: HomeInspectorService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        Button(inspector.isLoaded ? "Reload Homes" : "Load Homes", action: inspector.load)
            .buttonStyle(.borderedProminent)
            .experimentSession(inspector)
            .onAppear(perform: inspector.loadIfPreviouslyAuthorized)
            .confirmationDialog("Run this scene?", isPresented: Binding(get: { pendingScene != nil }, set: { if !$0 { pendingScene = nil } }),
                                titleVisibility: .visible, presenting: pendingScene) { scene in
                Button("Run \(scene.name)", role: .destructive) { inspector.runScene(scene.id) }
                Button("Cancel", role: .cancel) {}
            } message: { scene in
                Text("\(scene.name) changes a lock, door or alarm system:\n" + scene.actions.joined(separator: "\n"))
            }
        Text("No home to test with? Pair simulated accessories from the HomeKit Accessory Simulator (Additional Tools for Xcode) with the Home app, then inspect them here.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if !inspector.homes.isEmpty {
            Picker("Home", selection: Binding(get: { inspector.selectedHomeID }, set: inspector.selectHome)) {
                ForEach(inspector.homes) { home in
                    Text(home.name + (home.isPrimary ? " (primary)" : "")).tag(Optional(home.id))
                }
            }
            if let home = inspector.home {
                LabeledContent("Home hub", value: home.hubState)
                LabeledContent("Contents", value: "\(home.rooms.count) rooms · \(home.accessories.count) accessories · \(home.scenes.count) scenes · \(home.automations.count) automations")
                Picker("Show", selection: $pane) {
                    ForEach(HomeInspectorPane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch pane {
                case .accessories: accessories(in: home)
                case .scenes: scenes(in: home)
                case .automations: automations(in: home)
                }
            }
        }

        Section("Live change log (\(inspector.events.count))") {
            if inspector.events.isEmpty {
                Text("Turn on Notify for a characteristic to follow its changes through HMAccessoryDelegate. Reachability, firmware, scene and home changes are logged too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(inspector.events.prefix(40)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.date.formatted(date: .omitted, time: .standard)) · \(event.title)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(event.detail).font(.callout)
                    }
                }
                Button("Clear Log", action: inspector.clearEvents)
            }
        }

        OutputView(text: inspector.output, isError: inspector.isError)
            .confirmationDialog("Write to this accessory?", isPresented: Binding(get: { pendingWrite != nil }, set: { if !$0 { pendingWrite = nil } }),
                                titleVisibility: .visible, presenting: pendingWrite) { pending in
                Button("Write \(pending.valueText)", role: .destructive) { inspector.write(pending.value, to: pending.characteristicID) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("\(pending.title) controls a lock, door or alarm system. Writing \(pending.valueText) acts on the real accessory.")
            }
    }

    // MARK: Accessories

    @ViewBuilder
    private func accessories(in home: HomeInfo) -> some View {
        Picker("Room", selection: Binding(get: { inspector.selectedRoomID }, set: inspector.selectRoom)) {
            Text("All rooms").tag(UUID?.none)
            ForEach(home.rooms) { room in
                Text("\(room.name)\(room.isDefault ? " (default)" : "") · \(room.accessoryCount)").tag(Optional(room.id))
            }
        }
        if inspector.filteredAccessories.isEmpty {
            Text("No accessories here. Add one in the Home app or with the Matter Accessory Setup experiment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Picker("Accessory", selection: Binding(get: { inspector.selectedAccessoryID }, set: inspector.selectAccessory)) {
                ForEach(inspector.filteredAccessories) { accessory in
                    Text(accessory.name + (accessory.isReachable ? "" : " · unreachable")).tag(Optional(accessory.id))
                }
            }
        }
        if let accessory = inspector.accessory {
            HomeAccessoryDetails(accessory: accessory)
            Button("Read All Values", action: inspector.readAll)
                .disabled(!inspector.pending.isEmpty)
            ForEach(accessory.services) { service in
                Section {
                    ForEach(service.characteristics) { characteristic in
                        HomeCharacteristicRow(
                            characteristic: characteristic,
                            isPending: inspector.pending.contains(characteristic.id),
                            isNotifying: inspector.notifying.contains(characteristic.id),
                            read: { inspector.read(characteristic.id) },
                            setNotifications: { inspector.setNotifications($0, for: characteristic.id) },
                            write: { requestWrite($0, to: characteristic, accessory: accessory.name) })
                    }
                } header: {
                    Text(service.name == service.typeName ? service.typeName : "\(service.name) · \(service.typeName)")
                } footer: {
                    Text(serviceFooter(service)).font(.caption2.monospaced())
                }
            }
        }
    }

    private func serviceFooter(_ service: HomeServiceInfo) -> String {
        var parts = [service.type]
        if service.isPrimary { parts.append("primary") }
        if !service.isUserInteractive { parts.append("not user-interactive") }
        if service.linkedServiceCount > 0 { parts.append("\(service.linkedServiceCount) linked") }
        if let endpoint = service.matterEndpointID { parts.append("Matter endpoint \(endpoint)") }
        return parts.joined(separator: " · ")
    }

    private func requestWrite(_ value: HomeWriteValue, to characteristic: HomeCharacteristicInfo, accessory: String) {
        guard characteristic.needsConfirmation else {
            inspector.write(value, to: characteristic.id)
            return
        }
        pendingWrite = HomePendingWrite(
            characteristicID: characteristic.id, title: "\(accessory) · \(characteristic.name)", value: value,
            valueText: HomeInspectorFormat.describe(value.characteristicValue, units: characteristic.units, names: characteristic.namedValues))
    }

    // MARK: Scenes and automations

    @ViewBuilder
    private func scenes(in home: HomeInfo) -> some View {
        if home.scenes.isEmpty {
            Text("This home has no scenes (HMActionSet). Create one in the Home app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(home.scenes) { scene in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(scene.name).font(.headline)
                    Spacer(minLength: 8)
                    Button(inspector.runningScenes.contains(scene.id) || scene.isExecuting ? "Running…" : "Run") {
                        if scene.needsConfirmation { pendingScene = scene } else { inspector.runScene(scene.id) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(inspector.runningScenes.contains(scene.id) || scene.isExecuting)
                }
                Text(sceneSummary(scene)).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(scene.actions.enumerated()), id: \.offset) { _, action in
                    Text(action).font(.caption2.monospaced())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sceneSummary(_ scene: HomeSceneInfo) -> String {
        var parts = [scene.typeName, "\(scene.actions.count) action(s)"]
        if let date = scene.lastExecution { parts.append("last run \(date.formatted(date: .abbreviated, time: .shortened))") }
        if scene.needsConfirmation { parts.append("asks before running") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func automations(in home: HomeInfo) -> some View {
        if home.automations.isEmpty {
            Text("This home has no automations (HMTrigger). Automations run on a home hub (Apple TV or HomePod) and are created in the Home app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(home.automations) { automation in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Label(automation.name, systemImage: automation.kind == "Timer" ? "clock" : "bolt")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(automation.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(automation.isEnabled ? .green : .secondary)
                }
                Text(([automation.kind + " trigger"] + (automation.activation.map { [$0] } ?? [])).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(automation.details.enumerated()), id: \.offset) { _, detail in
                    Text(detail).font(.caption2.monospaced())
                }
                if !automation.scenes.isEmpty {
                    Text("Runs: " + automation.scenes.joined(separator: ", ")).font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct HomeAccessoryDetails: View {
    let accessory: HomeAccessoryInfo

    var body: some View {
        LabeledContent("Category", value: accessory.category)
        LabeledContent("Room", value: accessory.roomName)
        LabeledContent("Reachable", value: accessory.isReachable ? "Yes" : "No")
        if accessory.isBlocked { LabeledContent("Blocked", value: "Yes") }
        if accessory.isBridged { LabeledContent("Bridged", value: "Behind a bridge") }
        if accessory.bridgedAccessoryCount > 0 { LabeledContent("Bridge for", value: "\(accessory.bridgedAccessoryCount) accessories") }
        LabeledContent("Manufacturer", value: accessory.manufacturer ?? "Not reported")
        LabeledContent("Model", value: accessory.model ?? "Not reported")
        LabeledContent("Firmware", value: accessory.firmwareVersion ?? "Not reported")
        if let node = accessory.matterNodeID { LabeledContent("Matter node ID", value: String(format: "0x%016llX", node)) }
        if !accessory.profiles.isEmpty { LabeledContent("Profiles", value: accessory.profiles.joined(separator: ", ")) }
        LabeledContent("Identify", value: accessory.supportsIdentify ? "Supported" : "Not supported")
    }
}

private struct HomeCharacteristicRow: View {
    let characteristic: HomeCharacteristicInfo
    let isPending: Bool
    let isNotifying: Bool
    let read: () -> Void
    let setNotifications: (Bool) -> Void
    let write: (HomeWriteValue) -> Void

    private var allowsSlider: Bool {
        #if os(tvOS)
        false
        #else
        true
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(characteristic.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if isPending { ProgressView() }
                Text(characteristic.valueText)
                    .font(.callout.monospaced())
                    .multilineTextAlignment(.trailing)
            }
            Text(characteristic.metadataText).font(.caption).foregroundStyle(.secondary)
            if let description = characteristic.manufacturerDescription, description != characteristic.name {
                Text("Manufacturer description: \(description)").font(.caption).foregroundStyle(.secondary)
            }
            Text(characteristic.type).font(.caption2.monospaced()).foregroundStyle(.secondary)
            if characteristic.isReadable || characteristic.supportsNotifications {
                HStack {
                    if characteristic.isReadable {
                        Button("Read", action: read).buttonStyle(.bordered)
                    }
                    if characteristic.supportsNotifications {
                        Toggle("Notify", isOn: Binding(get: { isNotifying }, set: { setNotifications($0) }))
                            .fixedSize()
                    }
                }
            }
            if let control = HomeInspectorFormat.control(for: characteristic, allowsSlider: allowsSlider) {
                HomeWriteControlView(characteristic: characteristic, control: control, write: write)
            }
        }
        .padding(.vertical, 4)
        .disabled(isPending)
    }
}

private struct HomeWriteControlView: View {
    let characteristic: HomeCharacteristicInfo
    let control: HomeWriteControl
    let write: (HomeWriteValue) -> Void
    @State private var draft = 0.0
    @State private var text = ""

    private var unitSuffix: String { characteristic.units.map { " \($0)" } ?? "" }

    var body: some View {
        switch control {
        case .toggle:
            Toggle("Set value", isOn: Binding(get: { characteristic.value?.boolValue ?? false }, set: { write(.bool($0)) }))
        case .choice(let choices):
            Picker("Set value", selection: Binding(
                get: { characteristic.value?.intValue.flatMap { value in choices.contains { $0.value == value } ? value : nil } },
                set: { if let value = $0 { write(.integer(value)) } })) {
                Text("—").tag(Int?.none)
                ForEach(choices) { Text($0.title).tag(Optional($0.value)) }
            }
        case .levels(let levels):
            Picker("Set value", selection: Binding(
                get: { characteristic.value?.doubleValue.flatMap { value in levels.min { abs($0 - value) < abs($1 - value) } } },
                set: { if let value = $0 { write(.number(value)) } })) {
                Text("—").tag(Double?.none)
                ForEach(levels, id: \.self) { Text(HomeInspectorFormat.number($0) + unitSuffix).tag(Optional($0)) }
            }
        case .slider(let minimum, let maximum, let step):
            #if os(tvOS)
            EmptyView()
            #else
            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $draft, in: minimum...maximum, step: step) { editing in
                    guard !editing else { return }
                    write(characteristic.format?.isInteger == true ? .integer(Int(draft.rounded())) : .number(draft))
                }
                Text("Release to write \(HomeInspectorFormat.number(draft))\(unitSuffix)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { draft = min(maximum, max(minimum, characteristic.value?.doubleValue ?? minimum)) }
            .onChange(of: characteristic.value) { draft = min(maximum, max(minimum, characteristic.value?.doubleValue ?? draft)) }
            #endif
        case .text(let maxLength):
            HStack {
                TextField(maxLength.map { "New value (max \($0) characters)" } ?? "New value", text: $text)
                Button("Write") { write(.text(text)) }
                    .buttonStyle(.bordered)
                    .disabled(text.isEmpty || maxLength.map { text.count > $0 } == true)
            }
        case .unsupported(let reason):
            Label(reason, systemImage: "pencil.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MatterSetupRunView: View {
    @StateObject private var matter = MatterSetupExperimentService()
    @State private var mode: AccessorySetupMode = .systemFlow
    @State private var payload = ""
    @State private var isScanning = false

    var body: some View {
        Picker("Setup", selection: $mode) {
            ForEach(AccessorySetupMode.allCases) { Text($0.rawValue).tag($0) }
        }
        if mode != .systemFlow {
            TextField(mode == .matterPayload ? "MT:… or 11/21-digit pairing code" : "X-HM://…", text: $payload)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            #if os(iOS)
            if SetupCodeScannerView.isAvailable {
                Button(isScanning ? "Cancel Scan" : "Scan QR Code", systemImage: "qrcode.viewfinder") { isScanning.toggle() }
                if isScanning {
                    SetupCodeScannerView { code in
                        payload = code
                        isScanning = false
                    }
                    .frame(height: 260)
                }
            }
            #endif
            ForEach(matter.payloadDetails, id: \.0) { item in
                LabeledContent(item.0) { Text(item.1).font(.caption.monospaced()) }
            }
            if let key = mode.requiredEntitlement {
                LabeledContent("Needs") { Text(key).font(.caption.monospaced()) }
            }
        }
        Button(matter.isRunning ? "Setup in Progress…" : "Add Accessory to Apple Home") { matter.startSetup(mode: mode, payload: payload) }
            .buttonStyle(.borderedProminent)
            .disabled(matter.isRunning || (mode != .systemFlow && payload.isEmpty))
        if let home = matter.homeIdentifier {
            LabeledContent("Home") { Text(home).font(.caption.monospaced()) }
            ForEach(matter.accessoryIdentifiers, id: \.self) { accessory in
                LabeledContent("Accessory") { Text(accessory).font(.caption.monospaced()) }
            }
        }
        OutputView(text: matter.output, isError: matter.isError)
            .onChange(of: payload) { matter.inspect(mode: mode, payload: payload) }
            .onChange(of: mode) { matter.inspect(mode: mode, payload: payload) }
    }
}

struct HomeAccessoryBrowserRunView: View {
    @StateObject private var browser = HomeAccessoryBrowserService()

    var body: some View {
        Button(browser.isSearching ? "Stop Search" : "Search for Unpaired Accessories") {
            browser.isSearching ? browser.stop() : browser.start()
        }
        .buttonStyle(.borderedProminent)
        .experimentSession(browser)
        if browser.isSearching {
            ProgressView("Listening for accessories in pairing mode…").font(.caption)
        }
        ForEach(browser.accessories) { accessory in
            VStack(alignment: .leading, spacing: 2) {
                Text(accessory.name).font(.headline)
                Text("\(accessory.category)\(accessory.isBridged ? " · bridged" : "")").font(.caption).foregroundStyle(.secondary)
                let detail = [accessory.manufacturer, accessory.model].compactMap(\.self).joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                Text(accessory.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
        OutputView(text: browser.output, isError: browser.isError)
    }
}

#if os(iOS) && canImport(VisionKit)
/// Live camera QR scanner (VisionKit DataScannerViewController) that returns the first QR payload it reads.
struct SetupCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .accurate,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) { scanner.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                guard let value = barcode.payloadStringValue else { continue }
                dataScanner.stopScanning()
                onCode(value)
                return
            }
        }
    }
}
#endif
