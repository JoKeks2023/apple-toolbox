import Foundation
import Combine

#if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
import CoreBluetooth
#endif

struct PeripheralSubscriber: Identifiable, Equatable {
    let id: UUID
    /// Longest notification payload this central accepts (its ATT MTU − 3).
    let maximumUpdateLength: Int
}

/// Bluetooth Peripheral Mode: publishes the Apple Toolbox GATT service with CBPeripheralManager, advertises it,
/// answers reads and writes, and notifies subscribed centrals. The manager calls back on the main queue,
/// so the delegate stays main-actor isolated.
@MainActor
final class BluetoothPeripheralModeService: NSObject, ObservableObject {
    @Published private(set) var output = "Peripheral mode is ready. Start advertising to publish the Apple Toolbox service."
    @Published private(set) var managerState = "Not started"
    @Published private(set) var isRunning = false
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscribers: [PeripheralSubscriber] = []
    @Published private(set) var counter = 0
    @Published private(set) var lastWrite: Data?
    @Published private(set) var isAutoSending = false
    @Published private(set) var log: [GATTLogEntry] = []
    @Published var source: ToolboxGATTProfile.NotificationSource = .counter
    @Published var customText = "Hello from Apple Toolbox"

    #if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
    private var manager: CBPeripheralManager?
    private var feed: CBMutableCharacteristic?
    private var centrals: [UUID: CBCentral] = [:]
    private var feedValue = Data()
    /// Kept between the chunks of a long read so every offset reads the same snapshot.
    private var infoValue = Data()
    private var pendingNotification: Data?
    #endif
    private var autoSendTask: Task<Void, Never>?

    /// Smallest payload limit among the subscribed centrals; nil without subscribers.
    var notificationLimit: Int? { subscribers.map(\.maximumUpdateLength).min() }

    func start() {
        #if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
        guard !isRunning else { return }
        isRunning = true
        if let manager {
            if manager.state == .poweredOn {
                publishService(on: manager)
            } else {
                output = "Bluetooth is not ready: \(manager.state.displayName)."
            }
        } else {
            manager = CBPeripheralManager(delegate: self, queue: nil)
            output = "Waiting for Bluetooth permission and hardware state…"
        }
        #else
        output = "CBPeripheralManager is not available on this platform."
        #endif
    }

    func stop() {
        setAutoSend(false)
        #if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
        manager?.stopAdvertising()
        manager?.removeAllServices()
        feed = nil
        centrals.removeAll()
        pendingNotification = nil
        #endif
        if isRunning { appendLog(.info, "Stopped", "Advertising stopped and the Apple Toolbox service was removed.") }
        isRunning = false
        isAdvertising = false
        subscribers = []
        output = "Peripheral mode stopped."
    }

    func clearLog() { log.removeAll() }

    func sendNotification() {
        #if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
        guard isRunning, let manager, let feed else { output = "Start advertising first."; return }
        let nextCounter = counter + 1
        switch ToolboxGATTProfile.notificationPayload(source: source, counter: nextCounter, text: customText,
                                                      limit: notificationLimit ?? ToolboxGATTProfile.maximumValueLength) {
        case .failure(let error):
            appendLog(.error, "Notification not sent", error.localizedDescription)
            output = error.localizedDescription
        case .success(let data):
            if source == .counter { counter = nextCounter }
            feedValue = data
            guard !centrals.isEmpty else {
                appendLog(.info, "Feed updated", "\(GATTFormatting.summary(data)) · no central is subscribed; the value is kept for reads.")
                return
            }
            if manager.updateValue(data, for: feed, onSubscribedCentrals: nil) {
                appendLog(.notification, "Notified \(centrals.count) central\(centrals.count == 1 ? "" : "s")", GATTFormatting.summary(data))
            } else {
                pendingNotification = data
                appendLog(.info, "Transmit queue full", "updateValue returned false; the value is resent when Core Bluetooth calls peripheralManagerIsReady(toUpdateSubscribers:).")
            }
        }
        #endif
    }

    func setAutoSend(_ enabled: Bool) {
        autoSendTask?.cancel()
        autoSendTask = nil
        isAutoSending = enabled && isRunning
        guard isAutoSending else { return }
        autoSendTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if !self.subscribers.isEmpty { self.sendNotification() }
            }
        }
    }

    /// iOS suspends the app in the background unless it declares the bluetooth-peripheral background mode, which this build does not.
    func noteScenePhase(isBackground: Bool) {
        #if os(iOS)
        guard isRunning else { return }
        if isBackground {
            appendLog(.info, "App in background", "This build declares no bluetooth-peripheral background mode, so iOS suspends Apple Toolbox and advertising stops until you return.")
        } else {
            appendLog(.info, "App in foreground", "Advertising continues with the local name and the service UUID.")
        }
        #endif
    }

    private func appendLog(_ kind: GATTLogEntry.Kind, _ title: String, _ detail: String) {
        log.append(GATTLogEntry(kind: kind, title: title, detail: detail))
        if log.count > BluetoothExperimentService.logLimit { log.removeFirst(log.count - BluetoothExperimentService.logLimit) }
    }

    #if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
    private func publishService(on manager: CBPeripheralManager) {
        func userDescription(_ text: String) -> [CBMutableDescriptor] {
            [CBMutableDescriptor(type: CBUUID(string: CBUUIDCharacteristicUserDescriptionString), value: text)]
        }
        // Values stay nil so every read and write reaches the delegate instead of being answered from a cached value.
        let info = CBMutableCharacteristic(type: CBUUID(string: ToolboxGATTProfile.infoUUID), properties: [.read], value: nil, permissions: [.readable])
        info.descriptors = userDescription("Info: device summary (read)")
        let inbox = CBMutableCharacteristic(type: CBUUID(string: ToolboxGATTProfile.inboxUUID), properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        inbox.descriptors = userDescription("Inbox: up to 512 bytes (write)")
        let feed = CBMutableCharacteristic(type: CBUUID(string: ToolboxGATTProfile.feedUUID), properties: [.notify, .read], value: nil, permissions: [.readable])
        feed.descriptors = userDescription("Feed: counter or text (notify)")
        let service = CBMutableService(type: CBUUID(string: ToolboxGATTProfile.serviceUUID), primary: true)
        service.characteristics = [info, inbox, feed]
        self.feed = feed
        manager.removeAllServices()
        manager.add(service)
        output = "Publishing the Apple Toolbox service…"
    }

    private func refreshSubscribers() {
        subscribers = centrals.values.map { PeripheralSubscriber(id: $0.identifier, maximumUpdateLength: $0.maximumUpdateValueLength) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func characteristicName(_ uuid: CBUUID) -> String {
        GATTNames.name(for: uuid.uuidString) ?? uuid.uuidString
    }
    #endif
}

#if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
@MainActor extension BluetoothPeripheralModeService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        PermissionCenter.shared.invalidate()
        managerState = peripheral.state.displayName
        guard isRunning else { return }
        if peripheral.state == .poweredOn {
            if feed == nil { publishService(on: peripheral) }
        } else {
            // The local GATT database does not survive a power cycle; it is published again on the next poweredOn.
            feed = nil
            centrals.removeAll()
            refreshSubscribers()
            isAdvertising = false
            output = "Bluetooth is not ready: \(peripheral.state.displayName)."
            appendLog(.error, "Bluetooth \(peripheral.state.displayName)", "Advertising stopped. It restarts when Bluetooth is powered on again.")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            appendLog(.error, "Publishing failed", error.localizedDescription)
            output = "Could not publish the service: \(error.localizedDescription)"
            return
        }
        appendLog(.info, "Service published", ToolboxGATTProfile.serviceUUID)
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: ToolboxGATTProfile.localName,
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: ToolboxGATTProfile.serviceUUID)],
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            isAdvertising = false
            appendLog(.error, "Advertising failed", error.localizedDescription)
            output = "Could not start advertising: \(error.localizedDescription)"
        } else {
            isAdvertising = true
            appendLog(.info, "Advertising", "Local name “\(ToolboxGATTProfile.localName)” · service \(ToolboxGATTProfile.serviceUUID)")
            output = "Advertising as “\(ToolboxGATTProfile.localName)”. Open Core Bluetooth on a second device, scan, and connect."
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let uuid = request.characteristic.uuid.uuidString
        let value: Data
        switch uuid {
        case ToolboxGATTProfile.infoUUID:
            if request.offset == 0 {
                let version = ProcessInfo.processInfo.operatingSystemVersion
                infoValue = Data(ToolboxGATTProfile.infoText(platform: CurrentPlatform.value.rawValue, osVersion: "\(version.majorVersion).\(version.minorVersion)",
                                                             counter: counter, subscribers: centrals.count).utf8)
            }
            value = infoValue
        case ToolboxGATTProfile.feedUUID:
            value = feedValue
        default:
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        switch ToolboxGATTProfile.readResponse(for: value, offset: request.offset) {
        case .success(let chunk):
            request.value = chunk
            peripheral.respond(to: request, withResult: .success)
            if request.offset == 0 {
                appendLog(.read, "Read · \(characteristicName(request.characteristic.uuid))", "by \(request.central.identifier.uuidString.prefix(8))… · \(GATTFormatting.summary(value))")
            }
        case .failure(let failure):
            peripheral.respond(to: request, withResult: failure.attErrorCode)
            appendLog(.error, "Read rejected · \(characteristicName(request.characteristic.uuid))", "Offset \(request.offset) is beyond the \(value.count) B value.")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Core Bluetooth expects exactly one response, sent to the first request, for the whole batch.
        guard let first = requests.first else { return }
        guard requests.allSatisfy({ $0.characteristic.uuid.uuidString == ToolboxGATTProfile.inboxUUID }) else {
            peripheral.respond(to: first, withResult: .writeNotPermitted)
            appendLog(.error, "Write rejected", "Only the Inbox characteristic is writable.")
            return
        }
        let writes = requests.map { (offset: $0.offset, value: $0.value ?? Data()) }
        switch ToolboxGATTProfile.applyWrites(writes, to: lastWrite ?? Data()) {
        case .success(let value):
            lastWrite = value
            peripheral.respond(to: first, withResult: .success)
            appendLog(.write, "Write · Inbox", "by \(first.central.identifier.uuidString.prefix(8))… · \(GATTFormatting.summary(value))")
        case .failure(let failure):
            peripheral.respond(to: first, withResult: failure.attErrorCode)
            appendLog(.error, "Write rejected · Inbox", failure.localizedDescription)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        centrals[central.identifier] = central
        refreshSubscribers()
        appendLog(.info, "Subscribed · \(characteristicName(characteristic.uuid))",
                  "Central \(central.identifier.uuidString.prefix(8))… · accepts \(central.maximumUpdateValueLength) B per notification")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        centrals[central.identifier] = nil
        refreshSubscribers()
        appendLog(.info, "Unsubscribed · \(characteristicName(characteristic.uuid))", "Central \(central.identifier.uuidString.prefix(8))…")
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let pending = pendingNotification, let feed else { return }
        if peripheral.updateValue(pending, for: feed, onSubscribedCentrals: nil) {
            pendingNotification = nil
            appendLog(.notification, "Queued notification sent", GATTFormatting.summary(pending))
        }
    }
}

private extension ToolboxGATTProfile.ATTFailure {
    var attErrorCode: CBATTError.Code {
        switch self {
        case .invalidOffset: .invalidOffset
        case .invalidAttributeValueLength: .invalidAttributeValueLength
        }
    }
}
#endif
