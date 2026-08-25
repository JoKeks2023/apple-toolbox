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

@MainActor
final class NetworkExperimentService: ObservableObject {
    @Published private(set) var output = "Ready to inspect network path."
    @Published private(set) var isMonitoring = false
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "apple-toolbox.network-monitor")
    #endif

    func start() {
        #if canImport(Network)
        guard !isMonitoring else { return }
        isMonitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let interfaces = path.availableInterfaces.map { String(describing: $0.type) }.joined(separator: ", ")
                self?.output = "Status: \(String(describing: path.status))\nExpensive: \(path.isExpensive)\nConstrained: \(path.isConstrained)\nInterfaces: \(interfaces.isEmpty ? "None" : interfaces)"
            }
        }
        monitor.start(queue: queue)
        #else
        output = "Network.framework is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(Network)
        monitor.cancel()
        #endif
        isMonitoring = false
        output = "Network path monitoring stopped."
    }
}

@MainActor
final class BluetoothExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "Bluetooth scan is ready."
    @Published private(set) var isScanning = false
    #if canImport(CoreBluetooth) && !os(tvOS)
    private var central: CBCentralManager!
    #endif

    override init() {
        super.init()
        #if canImport(CoreBluetooth) && !os(tvOS)
        central = CBCentralManager(delegate: self, queue: nil)
        #endif
    }

    func start() {
        #if canImport(CoreBluetooth) && !os(tvOS)
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
        central.stopScan()
        #endif
        isScanning = false
        output = "Bluetooth scan stopped."
    }
}

#if canImport(CoreBluetooth) && !os(tvOS)
@MainActor extension BluetoothExperimentService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        output = "Bluetooth state: \(central.state.displayName)"
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unnamed peripheral"
        output = "Found: \(name)\nIdentifier: \(peripheral.identifier.uuidString)\nRSSI: \(RSSI) dBm"
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
    #if canImport(CoreNFC) && os(iOS)
    private var session: NFCNDEFReaderSession?
    #endif

    func start() {
        #if canImport(CoreNFC) && os(iOS)
        guard NFCNDEFReaderSession.readingAvailable else { output = "NFC reading is not available on this device."; return }
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold your iPhone near an NFC tag."
        self.session = session
        isScanning = true
        session.begin()
        #else
        output = "Core NFC is only available for NFC-capable iOS devices."
        #endif
    }

}

#if canImport(CoreNFC) && os(iOS)
extension NFCExperimentService: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let records = messages.flatMap(\.records)
        output = "Detected \(messages.count) NDEF message(s)\nRecords: \(records.count)\n" + records.map { "Type: \($0.typeNameFormat.rawValue), payload: \($0.payload.count) bytes" }.joined(separator: "\n")
        isScanning = false
    }
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        output = "NFC session ended: \(error.localizedDescription)"
        isScanning = false
    }
}
#endif
