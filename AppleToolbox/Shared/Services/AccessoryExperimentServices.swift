import Foundation
import Combine

#if canImport(AccessorySetupKit) && os(iOS)
import AccessorySetupKit
import CoreBluetooth
import UIKit
#endif

#if canImport(ExternalAccessory) && !os(watchOS)
import ExternalAccessory
#endif

#if canImport(CoreMIDI) && (os(iOS) || os(macOS))
import CoreMIDI
#endif

/// One line in an accessory experiment's live event log.
struct AccessoryEventEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let title: String
    let detail: String
    let isError: Bool
}

// MARK: - AccessorySetupKit

/// The AccessorySetupKit entries in Info.plist. Showing the picker for a Bluetooth item that is not declared
/// there crashes the app (documented), so the experiment checks them first.
nonisolated struct AccessorySetupKitDeclaration: Equatable, Sendable {
    let supports: [String]
    let bluetoothServices: [String]
    let bluetoothNames: [String]
    let bluetoothCompanyIdentifiers: [String]

    init(infoDictionary: [String: Any]) {
        supports = infoDictionary["NSAccessorySetupKitSupports"] as? [String] ?? []
        bluetoothServices = infoDictionary["NSAccessorySetupBluetoothServices"] as? [String] ?? []
        bluetoothNames = infoDictionary["NSAccessorySetupBluetoothNames"] as? [String] ?? []
        bluetoothCompanyIdentifiers = infoDictionary["NSAccessorySetupBluetoothCompanyIdentifiers"] as? [String] ?? []
    }

    static var current: AccessorySetupKitDeclaration { AccessorySetupKitDeclaration(infoDictionary: Bundle.main.infoDictionary ?? [:]) }

    /// Info.plist entries missing for a picker item that matches `serviceUUID` and `nameSubstring`.
    func missingEntries(serviceUUID: String, nameSubstring: String) -> [String] {
        var missing: [String] = []
        if !supports.contains("Bluetooth") { missing.append("NSAccessorySetupKitSupports → Bluetooth") }
        if !bluetoothServices.contains(where: { $0.caseInsensitiveCompare(serviceUUID) == .orderedSame }) {
            missing.append("NSAccessorySetupBluetoothServices → \(serviceUUID)")
        }
        if !bluetoothNames.contains(nameSubstring) { missing.append("NSAccessorySetupBluetoothNames → \(nameSubstring)") }
        return missing
    }
}

struct AccessorySetupItem: Identifiable, Equatable {
    let id: String
    let displayName: String
    let state: String
    let bluetoothIdentifier: UUID?
}

/// Activates an ASAccessorySession, lists the accessories authorized for the app, and shows the system
/// picker for the Apple Toolbox peripheral (a second device in Bluetooth Peripheral Mode).
@MainActor
final class AccessorySetupKitExperimentService: ObservableObject {
    @Published private(set) var output = "AccessorySetupKit session is not active."
    @Published private(set) var isSessionActive = false
    @Published private(set) var accessories: [AccessorySetupItem] = []
    @Published private(set) var events: [AccessoryEventEntry] = []
    let declaration = AccessorySetupKitDeclaration.current
    #if canImport(AccessorySetupKit) && os(iOS)
    private var session: ASAccessorySession?
    #endif

    var isActive: Bool { isSessionActive || hasSession }

    /// Entries the picker item for the Apple Toolbox peripheral still needs in Info.plist.
    var missingEntries: [String] {
        declaration.missingEntries(serviceUUID: ToolboxGATTProfile.serviceUUID, nameSubstring: ToolboxGATTProfile.localName)
    }

    private var hasSession: Bool {
        #if canImport(AccessorySetupKit) && os(iOS)
        session != nil
        #else
        false
        #endif
    }

    func activate() {
        #if canImport(AccessorySetupKit) && os(iOS)
        guard session == nil else { return }
        let session = ASAccessorySession()
        self.session = session
        // Events arrive on the main queue; the handler still hops explicitly so it never inherits isolation.
        session.activate(on: .main) { @Sendable [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        output = "Activating ASAccessorySession…"
        #else
        output = "AccessorySetupKit is only available on iPhone and iPad."
        #endif
    }

    func showPicker() {
        #if canImport(AccessorySetupKit) && os(iOS)
        guard let session, isSessionActive else { output = "Activate the session first."; return }
        let missing = missingEntries
        guard missing.isEmpty else {
            output = "Picker not shown. AccessorySetupKit terminates an app that discovers a Bluetooth accessory its Info.plist does not declare. Missing: \(missing.joined(separator: "; "))."
            appendEvent("Picker not shown", "Info.plist lacks: \(missing.joined(separator: "; "))", isError: true)
            return
        }
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: ToolboxGATTProfile.serviceUUID)
        descriptor.bluetoothNameSubstring = ToolboxGATTProfile.localName
        let image = UIImage(systemName: "dot.radiowaves.left.and.right") ?? UIImage()
        let item = ASPickerDisplayItem(name: "Apple Toolbox Peripheral", productImage: image, descriptor: descriptor)
        session.showPicker(for: [item]) { @Sendable [weak self] error in
            Task { @MainActor in self?.pickerFinished(error) }
        }
        output = "Showing the accessory picker…"
        #endif
    }

    func remove(_ id: AccessorySetupItem.ID) {
        #if canImport(AccessorySetupKit) && os(iOS)
        guard let session, let accessory = session.accessories.first(where: { Self.itemID(for: $0) == id }) else { return }
        session.removeAccessory(accessory) { @Sendable [weak self] error in
            Task { @MainActor in
                if let error { self?.appendEvent("Remove failed", error.localizedDescription, isError: true) }
            }
        }
        #endif
    }

    func stop() {
        #if canImport(AccessorySetupKit) && os(iOS)
        session?.invalidate()
        session = nil
        #endif
        if isSessionActive { appendEvent("Invalidated", "The session ended with the experiment.", isError: false) }
        isSessionActive = false
        accessories = []
        output = "AccessorySetupKit session invalidated."
    }

    private func appendEvent(_ title: String, _ detail: String, isError: Bool) {
        events.append(AccessoryEventEntry(title: title, detail: detail, isError: isError))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }

    #if canImport(AccessorySetupKit) && os(iOS)
    private static func itemID(for accessory: ASAccessory) -> String {
        accessory.bluetoothIdentifier?.uuidString ?? accessory.displayName
    }

    private func handle(_ event: ASAccessoryEvent) {
        let detail = [event.accessory?.displayName, event.error.map { "\($0.localizedDescription) (\(($0 as NSError).domain) \(($0 as NSError).code))" }]
            .compactMap { $0 }.joined(separator: " · ")
        appendEvent(event.eventType.displayName, detail.isEmpty ? "—" : detail, isError: event.error != nil)
        switch event.eventType {
        case .activated:
            isSessionActive = true
            refreshAccessories()
            output = "Session active. \(accessories.count) accessor\(accessories.count == 1 ? "y is" : "ies are") authorized for Apple Toolbox."
        case .invalidated:
            isSessionActive = false
            session = nil
            accessories = []
            output = "Session invalidated\(event.error.map { ": \($0.localizedDescription)" } ?? ".")"
        case .accessoryAdded, .accessoryRemoved, .accessoryChanged, .migrationComplete:
            refreshAccessories()
        default:
            break
        }
    }

    private func pickerFinished(_ error: Error?) {
        if let error {
            let nsError = error as NSError
            appendEvent("Picker finished with error", "\(error.localizedDescription) (\(nsError.domain) \(nsError.code))", isError: true)
            output = "Picker error: \(error.localizedDescription)"
        } else {
            output = "Picker closed. Added accessories appear below and connect through Core Bluetooth by their identifier."
        }
    }

    private func refreshAccessories() {
        accessories = (session?.accessories ?? []).map { accessory in
            AccessorySetupItem(id: Self.itemID(for: accessory), displayName: accessory.displayName,
                               state: accessory.state.displayName, bluetoothIdentifier: accessory.bluetoothIdentifier)
        }
    }
    #endif
}

#if canImport(AccessorySetupKit) && os(iOS)
private extension ASAccessoryEventType {
    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .activated: "Activated"
        case .invalidated: "Invalidated"
        case .migrationComplete: "Migration complete"
        case .accessoryAdded: "Accessory added"
        case .accessoryRemoved: "Accessory removed"
        case .accessoryChanged: "Accessory changed"
        case .accessoryDiscovered: "Accessory discovered"
        case .pickerDidPresent: "Picker presented"
        case .pickerDidDismiss: "Picker dismissed"
        case .pickerSetupBridging: "Setup: bridging"
        case .pickerSetupFailed: "Setup failed"
        case .pickerSetupPairing: "Setup: pairing"
        case .pickerSetupRename: "Setup: rename"
        @unknown default: "Event \(rawValue)"
        }
    }
}

private extension ASAccessory.AccessoryState {
    var displayName: String {
        switch self {
        case .unauthorized: "Unauthorized"
        case .awaitingAuthorization: "Awaiting authorization"
        case .authorized: "Authorized"
        @unknown default: "State \(rawValue)"
        }
    }
}
#endif

// MARK: - External Accessory

nonisolated struct ExternalAccessoryInfo: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let manufacturer: String
    let modelNumber: String
    let serialNumber: String
    let firmwareRevision: String
    let hardwareRevision: String
    let protocols: [String]
}

/// Lists MFi accessories through EAAccessoryManager and logs connect/disconnect notifications.
@MainActor
final class ExternalAccessoryExperimentService: ObservableObject {
    @Published private(set) var output = "External Accessory monitoring is ready."
    @Published private(set) var isMonitoring = false
    @Published private(set) var accessories: [ExternalAccessoryInfo] = []
    @Published private(set) var events: [AccessoryEventEntry] = []
    /// Protocols this app may open EASessions for; iOS only makes an accessory available when the app declares one of its protocols.
    let declaredProtocols = Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String] ?? []
    private var observers: [NSObjectProtocol] = []

    func start() {
        #if canImport(ExternalAccessory) && !os(watchOS)
        guard !isMonitoring else { return }
        let center = NotificationCenter.default
        let names: [(Notification.Name, Bool)] = [(.EAAccessoryDidConnect, true), (.EAAccessoryDidDisconnect, false)]
        for (name, connected) in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { @Sendable [weak self] notification in
                let info = (notification.userInfo?[EAAccessoryKey] as? EAAccessory).map(ExternalAccessoryInfo.init)
                Task { @MainActor in self?.accessoryChanged(info, connected: connected) }
            })
        }
        EAAccessoryManager.shared().registerForLocalNotifications()
        isMonitoring = true
        refresh()
        output = accessories.isEmpty
            ? "Listening for accessory connections. No accessory is available to Apple Toolbox right now."
            : "Listening for accessory connections. \(accessories.count) accessor\(accessories.count == 1 ? "y is" : "ies are") connected."
        #else
        output = "External Accessory is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(ExternalAccessory) && !os(watchOS)
        guard isMonitoring else { return }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        EAAccessoryManager.shared().unregisterForLocalNotifications()
        #endif
        isMonitoring = false
        output = "Stopped listening for accessory notifications."
    }

    func refresh() {
        #if canImport(ExternalAccessory) && !os(watchOS)
        accessories = EAAccessoryManager.shared().connectedAccessories.map(ExternalAccessoryInfo.init)
        #endif
    }

    private func accessoryChanged(_ info: ExternalAccessoryInfo?, connected: Bool) {
        let name = info.map { "\($0.name) · \($0.manufacturer)" } ?? "Unknown accessory"
        events.append(AccessoryEventEntry(title: connected ? "EAAccessoryDidConnect" : "EAAccessoryDidDisconnect",
                                          detail: name + (info.map { " · protocols: \($0.protocols.joined(separator: ", "))" } ?? ""), isError: false))
        refresh()
        output = "\(connected ? "Connected" : "Disconnected"): \(name)"
    }
}

#if canImport(ExternalAccessory) && !os(watchOS)
extension ExternalAccessoryInfo {
    /// Runs inside the notification observer, so it must not be main-actor isolated.
    nonisolated init(_ accessory: EAAccessory) {
        self.init(id: accessory.connectionID, name: accessory.name, manufacturer: accessory.manufacturer, modelNumber: accessory.modelNumber,
                  serialNumber: accessory.serialNumber, firmwareRevision: accessory.firmwareRevision,
                  hardwareRevision: accessory.hardwareRevision, protocols: accessory.protocolStrings)
    }
}
#endif

// MARK: - Bluetooth MIDI (Core MIDI)

nonisolated struct MIDIEndpointInfo: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String
    let manufacturer: String?
    let driver: String?
    let isOffline: Bool
    var isBluetooth: Bool { driver?.localizedCaseInsensitiveContains("bluetooth") == true || name.localizedCaseInsensitiveContains("bluetooth") }
}

struct MIDIEventEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let source: String
    let message: String
    let raw: String
}

/// Decodes Universal MIDI Packets (MIDI 1.0 protocol) into readable messages. Runs on Core MIDI's receive thread.
nonisolated enum MIDIMessageFormatter {
    /// Number of 32-bit words in a UMP message, from its message type (high nibble of the first word).
    static func wordCount(forMessageType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }

    /// Splits a packet's words into individual UMP messages.
    static func split(_ words: [UInt32]) -> [[UInt32]] {
        var messages: [[UInt32]] = []
        var index = 0
        while index < words.count {
            let count = wordCount(forMessageType: words[index] >> 28)
            let end = min(index + count, words.count)
            messages.append(Array(words[index..<end]))
            index = end
        }
        return messages
    }

    static func noteName(_ note: UInt32) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[Int(note % 12)])\(Int(note / 12) - 1)"
    }

    static func hex(_ words: [UInt32]) -> String {
        words.map { String(format: "%08X", $0) }.joined(separator: " ")
    }

    static func describe(_ message: [UInt32]) -> String {
        guard let word = message.first else { return "Empty packet" }
        let type = word >> 28
        let status = (word >> 16) & 0xFF
        let data1 = (word >> 8) & 0x7F
        let data2 = word & 0x7F
        switch type {
        case 0x0:
            return "Utility message"
        case 0x1:
            switch status {
            case 0xF1: return "MTC Quarter Frame · \(data1)"
            case 0xF2: return "Song Position · \(data1 | data2 << 7)"
            case 0xF3: return "Song Select · \(data1)"
            case 0xF6: return "Tune Request"
            case 0xF8: return "Timing Clock"
            case 0xFA: return "Start"
            case 0xFB: return "Continue"
            case 0xFC: return "Stop"
            case 0xFE: return "Active Sensing"
            case 0xFF: return "System Reset"
            default: return String(format: "System message 0x%02X", status)
            }
        case 0x2:
            let channel = (status & 0x0F) + 1
            switch status & 0xF0 {
            case 0x80: return "Note Off · ch \(channel) · \(noteName(data1)) (\(data1)) · velocity \(data2)"
            case 0x90 where data2 == 0: return "Note Off · ch \(channel) · \(noteName(data1)) (\(data1)) · Note On with velocity 0"
            case 0x90: return "Note On · ch \(channel) · \(noteName(data1)) (\(data1)) · velocity \(data2)"
            case 0xA0: return "Poly Pressure · ch \(channel) · \(noteName(data1)) (\(data1)) · \(data2)"
            case 0xB0: return "Control Change · ch \(channel) · CC \(data1) = \(data2)"
            case 0xC0: return "Program Change · ch \(channel) · program \(data1)"
            case 0xD0: return "Channel Pressure · ch \(channel) · \(data1)"
            case 0xE0:
                let value = Int(data1 | data2 << 7)
                return "Pitch Bend · ch \(channel) · \(value) (\(value >= 8192 ? "+" : "")\(value - 8192))"
            default: return String(format: "Channel message 0x%02X", status)
            }
        case 0x3:
            let form = ["complete", "start", "continue", "end"]
            let kind = Int((word >> 20) & 0xF)
            return "SysEx (\(kind < form.count ? form[kind] : "status \(kind)")) · \((word >> 16) & 0xF) bytes"
        case 0x4:
            return "MIDI 2.0 channel voice message"
        default:
            return String(format: "UMP message type 0x%X", type)
        }
    }
}

/// Lists Core MIDI sources and destinations (Bluetooth LE MIDI devices appear here once paired) and logs incoming messages.
@MainActor
final class MIDIExperimentService: ObservableObject {
    @Published private(set) var output = "Core MIDI is ready."
    @Published private(set) var isListening = false
    @Published private(set) var sources: [MIDIEndpointInfo] = []
    @Published private(set) var destinations: [MIDIEndpointInfo] = []
    @Published private(set) var events: [MIDIEventEntry] = []

    #if canImport(CoreMIDI) && (os(iOS) || os(macOS))
    /// Core MIDI clients are never disposed: disposing an app's last client can stop the MIDI server for the process.
    private static var client = MIDIClientRef()
    /// The service that receives setup-change notifications from the shared client.
    private static weak var current: MIDIExperimentService?
    private var inputPort = MIDIPortRef()
    private var connectedSources: Set<MIDIEndpointRef> = []
    #endif

    func start() {
        #if canImport(CoreMIDI) && (os(iOS) || os(macOS))
        guard !isListening else { return }
        Self.current = self
        if Self.client == 0 {
            var client = MIDIClientRef()
            let status = MIDIClientCreateWithBlock("Apple Toolbox" as CFString, &client) { @Sendable notification in
                let messageID = notification.pointee.messageID.rawValue
                Task { @MainActor in MIDIExperimentService.current?.setupChanged(messageID) }
            }
            guard status == noErr else { output = "MIDIClientCreateWithBlock failed with OSStatus \(status)."; return }
            Self.client = client
        }
        var port = MIDIPortRef()
        // Core MIDI calls this block on its own high-priority receive thread.
        let status = MIDIInputPortCreateWithProtocol(Self.client, "Apple Toolbox Input" as CFString, ._1_0, &port) { @Sendable eventList, sourceRefCon in
            let source = MIDIEndpointRef(truncatingIfNeeded: UInt(bitPattern: sourceRefCon))
            let messages = eventList.unsafeSequence().flatMap { MIDIMessageFormatter.split(Array($0.words())) }
            Task { @MainActor in MIDIExperimentService.current?.received(messages, from: source) }
        }
        guard status == noErr else { output = "MIDIInputPortCreateWithProtocol failed with OSStatus \(status)."; return }
        inputPort = port
        isListening = true
        refreshEndpoints()
        output = "Listening to \(connectedSources.count) MIDI source\(connectedSources.count == 1 ? "" : "s"). Play a note on a connected device."
        #else
        output = "Core MIDI input is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(CoreMIDI) && (os(iOS) || os(macOS))
        guard isListening else { return }
        for source in connectedSources { MIDIPortDisconnectSource(inputPort, source) }
        connectedSources.removeAll()
        MIDIPortDispose(inputPort)
        inputPort = 0
        if Self.current === self { Self.current = nil }
        #endif
        isListening = false
        output = "Stopped listening to MIDI sources."
    }

    func clearEvents() { events.removeAll() }

    func refreshEndpoints() {
        #if canImport(CoreMIDI) && (os(iOS) || os(macOS))
        sources = (0..<MIDIGetNumberOfSources()).map { Self.info(for: MIDIGetSource($0)) }
        destinations = (0..<MIDIGetNumberOfDestinations()).map { Self.info(for: MIDIGetDestination($0)) }
        guard isListening else { return }
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0, !connectedSources.contains(source) else { continue }
            if MIDIPortConnectSource(inputPort, source, UnsafeMutableRawPointer(bitPattern: UInt(source))) == noErr {
                connectedSources.insert(source)
            }
        }
        #endif
    }

    #if canImport(CoreMIDI) && (os(iOS) || os(macOS))

    private func setupChanged(_ messageID: Int32) {
        guard messageID == MIDINotificationMessageID.msgSetupChanged.rawValue else { return }
        let before = Set(sources.map(\.name))
        refreshEndpoints()
        let after = Set(sources.map(\.name))
        let added = after.subtracting(before), removed = before.subtracting(after)
        if !added.isEmpty || !removed.isEmpty {
            output = "MIDI setup changed." + (added.isEmpty ? "" : " Added: \(added.sorted().joined(separator: ", ")).") + (removed.isEmpty ? "" : " Removed: \(removed.sorted().joined(separator: ", ")).")
        }
    }

    private func received(_ messages: [[UInt32]], from source: MIDIEndpointRef) {
        let name = sources.first { $0.id == source }?.name ?? "Source \(source)"
        for message in messages where message.first.map({ $0 >> 28 }) != 0 {
            events.append(MIDIEventEntry(source: name, message: MIDIMessageFormatter.describe(message), raw: MIDIMessageFormatter.hex(message)))
        }
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }

    private static func info(for endpoint: MIDIEndpointRef) -> MIDIEndpointInfo {
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        return MIDIEndpointInfo(id: endpoint, name: string(endpoint, kMIDIPropertyDisplayName) ?? string(endpoint, kMIDIPropertyName) ?? "Unnamed endpoint",
                                manufacturer: string(endpoint, kMIDIPropertyManufacturer), driver: string(endpoint, kMIDIPropertyDriverOwner),
                                isOffline: offline != 0)
    }

    private static func string(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
    #endif
}

// MARK: - Live status

extension ExperimentAvailability {
    static func accessorySetupKit() -> ExperimentStatus {
        #if canImport(AccessorySetupKit) && os(iOS)
        let missing = AccessorySetupKitDeclaration.current.missingEntries(serviceUUID: ToolboxGATTProfile.serviceUUID, nameSubstring: ToolboxGATTProfile.localName)
        return missing.isEmpty ? .available : .unavailable
        #else
        return .platformUnsupported
        #endif
    }

    static func externalAccessory() -> ExperimentStatus {
        #if canImport(ExternalAccessory) && !os(watchOS)
        EAAccessoryManager.shared().connectedAccessories.isEmpty ? .unavailable : .available
        #else
        .platformUnsupported
        #endif
    }
}
