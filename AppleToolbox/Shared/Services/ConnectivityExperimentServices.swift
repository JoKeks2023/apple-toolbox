import Foundation
import Combine

#if canImport(Network)
import Network
#endif

#if canImport(CoreBluetooth) && !os(tvOS)
import CoreBluetooth
#endif

#if canImport(CoreNFC) && os(iOS)
import CoreNFC
#endif

struct NetworkInterfaceResult: Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
}

@MainActor
final class NetworkExperimentService: ObservableObject {
    @Published private(set) var output = "Ready to inspect network path."
    @Published private(set) var isMonitoring = false
    @Published private(set) var interfaces: [NetworkInterfaceResult] = []
    #if canImport(Network)
    /// A cancelled NWPathMonitor cannot be restarted, so every start creates a new one.
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "apple-toolbox.network-monitor")
    #endif

    func start() {
        #if canImport(Network)
        guard !isMonitoring else { return }
        isMonitoring = true
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            Task { @MainActor in
                let results = path.availableInterfaces.map { NetworkInterfaceResult(id: $0.name, name: $0.name, type: String(describing: $0.type)) }
                self?.interfaces = results
                let names = results.map { "\($0.name) (\($0.type))" }.joined(separator: ", ")
                self?.output = "Status: \(String(describing: path.status))\nExpensive: \(path.isExpensive)\nConstrained: \(path.isConstrained)\nInterfaces: \(names.isEmpty ? "None" : names)"
            }
        }
        monitor.start(queue: queue)
        #else
        output = "Network.framework is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
        isMonitoring = false
        interfaces = []
        output = "Network path monitoring stopped."
    }
}

@MainActor
struct BluetoothPeripheralResult: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var manufacturerDataBytes: Int
    var lastSeen: Date
}

@MainActor
final class BluetoothExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Bluetooth scan is ready."
    @Published private(set) var isScanning = false
    @Published private(set) var peripherals: [BluetoothPeripheralResult] = []
    #if canImport(CoreBluetooth) && !os(tvOS)
    private var central: CBCentralManager?
    #endif

    override init() {
        super.init()
    }

    func start() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        peripherals.removeAll()
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

    func stop() {
        #if canImport(CoreBluetooth) && !os(tvOS)
        central?.stopScan()
        #endif
        isScanning = false
        output = "Bluetooth scan stopped."
    }

    func clearResults() {
        peripherals.removeAll()
        output = "Bluetooth results cleared."
    }
}

#if canImport(CoreBluetooth) && !os(tvOS)
@MainActor extension BluetoothExperimentService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        PermissionCenter.shared.invalidate()
        output = "Bluetooth state: \(central.state.displayName)"
        if central.state == .poweredOn, isScanning {
            central.scanForPeripherals(withServices: nil)
            output = "Scanning for nearby Bluetooth LE peripherals…"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unnamed peripheral"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let manufacturerDataBytes = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.count ?? 0
        let result = BluetoothPeripheralResult(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
                                               advertisedServices: services, manufacturerDataBytes: manufacturerDataBytes, lastSeen: Date())
        if let index = peripherals.firstIndex(where: { $0.id == result.id }) {
            peripherals[index] = result
        } else {
            peripherals.append(result)
        }
        peripherals.sort { $0.rssi > $1.rssi }
        output = "Found \(peripherals.count) nearby peripheral\(peripherals.count == 1 ? "" : "s")."
    }
}
private extension CBManagerState {
    var displayName: String {
        switch self { case .unknown: "Unknown"; case .resetting: "Resetting"; case .unsupported: "Unsupported"; case .unauthorized: "Unauthorized"; case .poweredOff: "Powered Off"; case .poweredOn: "Powered On"; @unknown default: "Unknown" }
    }
}
#endif

@MainActor
final class NFCExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "NFC tag reading is ready."
    @Published private(set) var isScanning = false
    @Published private(set) var records: [NFCRecordResult] = []
    #if canImport(CoreNFC) && os(iOS)
    private var session: NFCNDEFReaderSession?
    #endif

    func start() {
        #if canImport(CoreNFC) && os(iOS)
        guard NFCNDEFReaderSession.readingAvailable else { output = "NFC reading is not available on this device."; return }
        records.removeAll()
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold your iPhone near an NFC tag."
        self.session = session
        isScanning = true
        session.begin()
        #else
        output = "Core NFC is only available for NFC-capable iOS devices."
        #endif
    }

    func stop() {
        #if canImport(CoreNFC) && os(iOS)
        session?.invalidate()
        session = nil
        #endif
        isScanning = false
    }
}

#if canImport(CoreNFC) && os(iOS)
extension NFCExperimentService: NFCNDEFReaderSessionDelegate {
    // Core NFC calls the delegate on its own serial queue; results hop to the main actor.
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let records = messages.flatMap(\.records).enumerated().map { index, record in
            NFCRecordResult(id: index, format: record.typeNameFormat.rawValue, type: String(data: record.type, encoding: .utf8) ?? "Unknown", payloadBytes: record.payload.count)
        }
        let messageCount = messages.count
        Task { @MainActor [weak self] in
            self?.records = records
            self?.output = "Detected \(messageCount) NDEF message(s) with \(records.count) record(s)."
            self?.isScanning = false
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            isScanning = false
            switch code {
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                break // Expected after a successful read with invalidateAfterFirstRead.
            case .readerSessionInvalidationErrorUserCanceled:
                if records.isEmpty { output = "NFC scan cancelled." }
            default:
                output = "NFC session error: \(message)"
            }
        }
    }
}
#endif

struct NFCRecordResult: Identifiable, Equatable {
    let id: Int
    let format: UInt8
    let type: String
    let payloadBytes: Int
}
