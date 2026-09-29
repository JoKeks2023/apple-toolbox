import Foundation
import Combine

#if canImport(Network)
import Network
#endif

#if canImport(CoreBluetooth) && !os(tvOS)
import CoreBluetooth
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
