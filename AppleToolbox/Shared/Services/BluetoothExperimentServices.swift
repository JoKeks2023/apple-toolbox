import Foundation
import Combine

#if canImport(CoreBluetooth) && !os(tvOS)
import CoreBluetooth
#endif

struct BluetoothPeripheralResult: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var manufacturerDataBytes: Int
    /// `CBAdvertisementDataIsConnectable`; nil when the advertisement does not say.
    var isConnectable: Bool?
    var lastSeen: Date
}

enum BluetoothConnectionState: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting…"
    case discovering = "Discovering GATT database…"
    case connected = "Connected"
    case disconnecting = "Disconnecting…"
}

struct GATTDescriptorNode: Identifiable, Equatable {
    let id: ObjectIdentifier
    let uuid: String
    let name: String?
    let value: String
}

struct GATTCharacteristicNode: Identifiable, Equatable {
    let id: ObjectIdentifier
    let uuid: String
    let name: String?
    let properties: [String]
    let canRead: Bool
    let canWrite: Bool
    let canWriteWithoutResponse: Bool
    let canSubscribe: Bool
    let isNotifying: Bool
    let value: Data?
    let descriptors: [GATTDescriptorNode]
}

struct GATTServiceNode: Identifiable, Equatable {
    let id: ObjectIdentifier
    let uuid: String
    let name: String?
    let isPrimary: Bool
    let characteristics: [GATTCharacteristicNode]
}

struct GATTWriteLimits: Equatable {
    /// Long writes (prepare + execute) let Core Bluetooth split confirmed writes up to this length.
    let withResponse: Int
    /// A write command must fit into one ATT packet: ATT MTU − 3.
    let withoutResponse: Int
}

struct GATTLogEntry: Identifiable, Equatable {
    enum Kind: String { case info = "Info", read = "Read", write = "Write", notification = "Notify", error = "Error" }
    let id = UUID()
    let date = Date()
    let kind: Kind
    let title: String
    let detail: String
}

/// Scans for BLE peripherals and, for one connected peripheral, explores its GATT database.
/// The central manager delivers every callback on the main queue, so the delegates stay main-actor isolated.
@MainActor
final class BluetoothExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Bluetooth scan is ready."
    @Published private(set) var isScanning = false
    @Published private(set) var peripherals: [BluetoothPeripheralResult] = []
    @Published private(set) var connectionState: BluetoothConnectionState = .disconnected
    @Published private(set) var connectedPeripheralID: UUID?
    @Published private(set) var connectedName = ""
    @Published private(set) var services: [GATTServiceNode] = []
    @Published private(set) var rssi: Int?
    @Published private(set) var writeLimits: GATTWriteLimits?
    @Published private(set) var log: [GATTLogEntry] = []

    static let logLimit = 200
    var isConnected: Bool { connectionState != .disconnected }

    #if canImport(CoreBluetooth) && !os(tvOS)
    private var central: CBCentralManager?
    /// Core Bluetooth drops a discovered peripheral unless the app keeps a strong reference to it.
    private var discovered: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    /// Service and characteristic discoveries still outstanding; the explorer is ready when this reaches zero.
    private var pendingDiscoveries = 0
    /// Characteristics with an explicit read in flight, so their update is logged as a read, not a notification.
    private var pendingReads: Set<ObjectIdentifier> = []
    #endif

    override init() {
        super.init()
    }

    func start() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        peripherals.removeAll()
        discovered = discovered.filter { $0.key == connected?.identifier }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
            isScanning = true
            output = "Waiting for Bluetooth permission and hardware state…"
            return
        }
        guard let central else { return }
        guard central.state == .poweredOn else { output = "Bluetooth is not ready: \(central.state.displayName)."; return }
        central.scanForPeripherals(withServices: nil)
        isScanning = true
        output = "Scanning for nearby Bluetooth LE peripherals…"
        #else
        output = "Core Bluetooth scanning is not available on this platform."
        #endif
    }

    func stopScan() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        central?.stopScan()
        #endif
        isScanning = false
        output = "Bluetooth scan stopped."
    }

    /// Ends the scan and any connection (experiment lifecycle).
    func stop() {
        stopScan()
        #if canImport(CoreBluetooth) && !os(tvOS)
        if let connected {
            central?.cancelPeripheralConnection(connected)
            appendLog(.info, "Disconnected", "Connection closed because the experiment ended.")
        }
        resetConnection()
        #endif
        output = "Bluetooth scan stopped and connection closed."
    }

    func clearResults() {
        peripherals.removeAll()
        #if canImport(CoreBluetooth) && !os(tvOS)
        discovered = discovered.filter { $0.key == connected?.identifier }
        #endif
        output = "Bluetooth results cleared."
    }

    func clearLog() { log.removeAll() }

    // MARK: GATT explorer

    func connect(to id: UUID) {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let central, central.state == .poweredOn else { output = "Bluetooth is not powered on."; return }
        guard let peripheral = discovered[id] else { output = "This peripheral is no longer cached. Scan again."; return }
        if let connected {
            central.cancelPeripheralConnection(connected)
            appendLog(.info, "Disconnected", connectedName)
            resetConnection()
        }
        if isScanning {
            central.stopScan()
            isScanning = false
        }
        let name = peripherals.first { $0.id == id }?.name ?? peripheral.name ?? "Unnamed peripheral"
        connected = peripheral
        discovered[id] = peripheral
        peripheral.delegate = self
        connectedPeripheralID = id
        connectedName = name
        connectionState = .connecting
        appendLog(.info, "Connecting", "\(name) · \(id.uuidString)")
        central.connect(peripheral)
        output = "Connecting to \(name)… The scan was stopped. Core Bluetooth never times out a connection attempt; tap Disconnect to cancel."
        #endif
    }

    func disconnect() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected, let central else { return }
        central.cancelPeripheralConnection(connected)
        if connectionState == .connecting {
            // A pending connection is simply withdrawn; there is no link to tear down.
            appendLog(.info, "Connection attempt cancelled", connectedName)
            resetConnection()
            output = "Connection attempt cancelled."
        } else {
            connectionState = .disconnecting
            output = "Disconnecting from \(connectedName)…"
        }
        #endif
    }

    func rediscover() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected, connected.state == .connected else { return }
        pendingDiscoveries = 1
        pendingReads.removeAll()
        connectionState = .discovering
        appendLog(.info, "Rediscovering services", connectedName)
        connected.discoverServices(nil)
        #endif
    }

    func readRSSI() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected, connected.state == .connected else { return }
        connected.readRSSI()
        #endif
    }

    func read(_ id: GATTCharacteristicNode.ID) {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected, let characteristic = characteristic(for: id) else { return }
        pendingReads.insert(id)
        connected.readValue(for: characteristic)
        #endif
    }

    func readDescriptor(_ id: GATTDescriptorNode.ID) {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected else { return }
        let descriptors = (connected.services ?? []).flatMap { $0.characteristics ?? [] }.flatMap { $0.descriptors ?? [] }
        guard let descriptor = descriptors.first(where: { ObjectIdentifier($0) == id }) else { return }
        connected.readValue(for: descriptor)
        #endif
    }

    func setNotifications(_ enabled: Bool, for id: GATTCharacteristicNode.ID) {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected, let characteristic = characteristic(for: id) else { return }
        connected.setNotifyValue(enabled, for: characteristic)
        #endif
    }

    func write(_ data: Data, to id: GATTCharacteristicNode.ID, kind: GATTWriteKind) {
        #if canImport(CoreBluetooth) && !os(tvOS)
        guard let connected, let characteristic = characteristic(for: id) else { return }
        let name = displayName(for: characteristic.uuid)
        let type: CBCharacteristicWriteType = kind == .withResponse ? .withResponse : .withoutResponse
        let limit = connected.maximumWriteValueLength(for: type)
        guard data.count <= limit else {
            appendLog(.error, "Write rejected locally · \(name)", "\(data.count) B exceeds the \(limit) B maximum for a write \(kind.rawValue.lowercased()).")
            return
        }
        if kind == .withoutResponse, !connected.canSendWriteWithoutResponse {
            appendLog(.error, "Write queue full · \(name)", "canSendWriteWithoutResponse is false; Core Bluetooth would drop the packet. Try again in a moment.")
            return
        }
        connected.writeValue(data, for: characteristic, type: type)
        if kind == .withoutResponse {
            appendLog(.write, "Sent without response · \(name)", "\(GATTFormatting.summary(data)) · the peripheral does not confirm write commands")
        } else {
            appendLog(.info, "Write requested · \(name)", GATTFormatting.summary(data))
        }
        #endif
    }

    private func appendLog(_ kind: GATTLogEntry.Kind, _ title: String, _ detail: String) {
        log.append(GATTLogEntry(kind: kind, title: title, detail: detail))
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    #if canImport(CoreBluetooth) && !os(tvOS)
    private func characteristic(for id: ObjectIdentifier) -> CBCharacteristic? {
        (connected?.services ?? []).lazy.flatMap { $0.characteristics ?? [] }.first { ObjectIdentifier($0) == id }
    }

    private func displayName(for uuid: CBUUID) -> String {
        GATTNames.name(for: uuid.uuidString) ?? systemName(for: uuid) ?? uuid.uuidString
    }

    /// Core Bluetooth describes UUIDs it knows by name; unknown ones describe as their UUID string.
    private func systemName(for uuid: CBUUID) -> String? {
        uuid.description == uuid.uuidString ? nil : uuid.description
    }

    private func resetConnection() {
        connected?.delegate = nil
        connected = nil
        connectedPeripheralID = nil
        connectedName = ""
        connectionState = .disconnected
        services = []
        rssi = nil
        writeLimits = nil
        pendingDiscoveries = 0
        pendingReads.removeAll()
    }

    private func refreshTree() {
        services = (connected?.services ?? []).map { service in
            GATTServiceNode(id: ObjectIdentifier(service), uuid: service.uuid.uuidString,
                            name: GATTNames.name(for: service.uuid.uuidString) ?? systemName(for: service.uuid),
                            isPrimary: service.isPrimary, characteristics: (service.characteristics ?? []).map(node(for:)))
        }
    }

    private func node(for characteristic: CBCharacteristic) -> GATTCharacteristicNode {
        let properties = characteristic.properties
        let descriptors = (characteristic.descriptors ?? []).map { descriptor in
            GATTDescriptorNode(id: ObjectIdentifier(descriptor), uuid: descriptor.uuid.uuidString,
                               name: GATTNames.name(for: descriptor.uuid.uuidString) ?? systemName(for: descriptor.uuid),
                               value: GATTFormatting.descriptorValue(descriptor.value, uuid: descriptor.uuid.uuidString))
        }
        return GATTCharacteristicNode(id: ObjectIdentifier(characteristic), uuid: characteristic.uuid.uuidString,
                                      name: GATTNames.name(for: characteristic.uuid.uuidString) ?? systemName(for: characteristic.uuid),
                                      properties: GATTFormatting.propertyNames(properties),
                                      canRead: properties.contains(.read), canWrite: properties.contains(.write),
                                      canWriteWithoutResponse: properties.contains(.writeWithoutResponse),
                                      canSubscribe: !properties.isDisjoint(with: [.notify, .indicate]),
                                      isNotifying: characteristic.isNotifying, value: characteristic.value, descriptors: descriptors)
    }

    private func finishDiscoveryStep() {
        pendingDiscoveries = max(0, pendingDiscoveries - 1)
        refreshTree()
        guard pendingDiscoveries == 0, connectionState == .discovering else { return }
        connectionState = .connected
        let characteristicCount = services.reduce(0) { $0 + $1.characteristics.count }
        output = "Connected to \(connectedName): \(services.count) service\(services.count == 1 ? "" : "s"), \(characteristicCount) characteristic\(characteristicCount == 1 ? "" : "s")."
        appendLog(.info, "GATT database discovered", output)
    }
    #endif
}

#if canImport(CoreBluetooth) && !os(tvOS)
@MainActor extension BluetoothExperimentService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        PermissionCenter.shared.invalidate()
        output = "Bluetooth state: \(central.state.displayName)"
        if central.state != .poweredOn, connected != nil {
            appendLog(.error, "Connection lost", "Bluetooth state changed to \(central.state.displayName).")
            resetConnection()
        }
        if central.state == .poweredOn, isScanning {
            central.scanForPeripherals(withServices: nil)
            output = "Scanning for nearby Bluetooth LE peripherals…"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unnamed peripheral"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let manufacturerDataBytes = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.count ?? 0
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        discovered[peripheral.identifier] = peripheral
        let result = BluetoothPeripheralResult(id: peripheral.identifier, name: name, rssi: RSSI.intValue, advertisedServices: services,
                                               manufacturerDataBytes: manufacturerDataBytes, isConnectable: connectable, lastSeen: Date())
        if let index = peripherals.firstIndex(where: { $0.id == result.id }) {
            peripherals[index] = result
        } else {
            peripherals.append(result)
        }
        peripherals.sort { $0.rssi > $1.rssi }
        output = "Found \(peripherals.count) nearby peripheral\(peripherals.count == 1 ? "" : "s")."
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == connected?.identifier else { return }
        connectionState = .discovering
        writeLimits = GATTWriteLimits(withResponse: peripheral.maximumWriteValueLength(for: .withResponse),
                                      withoutResponse: peripheral.maximumWriteValueLength(for: .withoutResponse))
        appendLog(.info, "Connected", "\(connectedName) · discovering services")
        output = "Connected to \(connectedName). Discovering services, characteristics and descriptors…"
        pendingDiscoveries = 1
        peripheral.discoverServices(nil)
        peripheral.readRSSI()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == connected?.identifier else { return }
        let reason = error?.localizedDescription ?? "No error returned."
        appendLog(.error, "Connection failed", reason)
        output = "Could not connect to \(connectedName): \(reason)"
        resetConnection()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == connected?.identifier else { return }
        let name = connectedName
        if let error {
            appendLog(.error, "Disconnected", "\(name): \(error.localizedDescription)")
            output = "\(name) disconnected: \(error.localizedDescription)"
        } else {
            appendLog(.info, "Disconnected", name)
            output = "Disconnected from \(name)."
        }
        resetConnection()
    }
}

@MainActor extension BluetoothExperimentService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { appendLog(.error, "Service discovery failed", error.localizedDescription) }
        let services = peripheral.services ?? []
        pendingDiscoveries += services.count
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
        finishDiscoveryStep()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { appendLog(.error, "Characteristic discovery failed · \(displayName(for: service.uuid))", error.localizedDescription) }
        let characteristics = service.characteristics ?? []
        pendingDiscoveries += characteristics.count
        characteristics.forEach { peripheral.discoverDescriptors(for: $0) }
        finishDiscoveryStep()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let error { appendLog(.error, "Descriptor discovery failed · \(displayName(for: characteristic.uuid))", error.localizedDescription) }
        finishDiscoveryStep()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let id = ObjectIdentifier(characteristic)
        let wasRead = pendingReads.remove(id) != nil
        let name = displayName(for: characteristic.uuid)
        if let error {
            appendLog(.error, "\(wasRead ? "Read" : "Update") failed · \(name)", error.localizedDescription)
        } else {
            appendLog(wasRead ? .read : .notification, name, GATTFormatting.summary(characteristic.value))
        }
        refreshTree()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let name = displayName(for: characteristic.uuid)
        if let error {
            appendLog(.error, "Write failed · \(name)", error.localizedDescription)
        } else {
            appendLog(.write, "Write confirmed · \(name)", "The peripheral acknowledged the write request.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let name = displayName(for: characteristic.uuid)
        if let error {
            appendLog(.error, "Subscription failed · \(name)", error.localizedDescription)
        } else {
            appendLog(.info, characteristic.isNotifying ? "Subscribed · \(name)" : "Unsubscribed · \(name)",
                      characteristic.isNotifying ? "Updates now arrive in this log." : "The peripheral stops sending updates.")
        }
        refreshTree()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        let name = displayName(for: descriptor.uuid)
        if let error {
            appendLog(.error, "Descriptor read failed · \(name)", error.localizedDescription)
        } else {
            appendLog(.read, name, GATTFormatting.descriptorValue(descriptor.value, uuid: descriptor.uuid.uuidString))
        }
        refreshTree()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error {
            appendLog(.error, "RSSI read failed", error.localizedDescription)
        } else {
            rssi = RSSI.intValue
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        appendLog(.info, "Services changed", "The peripheral invalidated \(invalidatedServices.count) service(s); rediscovering.")
        rediscover()
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        if let name = peripheral.name { connectedName = name }
    }
}

extension CBManagerState {
    var displayName: String {
        switch self { case .unknown: "Unknown"; case .resetting: "Resetting"; case .unsupported: "Unsupported"; case .unauthorized: "Unauthorized"; case .poweredOff: "Powered Off"; case .poweredOn: "Powered On"; @unknown default: "Unknown" }
    }
}
#endif
