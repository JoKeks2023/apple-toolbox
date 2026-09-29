import Foundation
import Combine

#if canImport(Network)
import Network
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
