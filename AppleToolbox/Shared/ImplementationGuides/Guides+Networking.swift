import Foundation

nonisolated extension ImplementationGuides {
    static let networking: [String: ImplementationGuide] = [
        "network-path": ImplementationGuide(
            snippet: #"""
            import Network

            /// Watches the current network path and opens a TLS connection, logging every state change.
            final class ConnectionProbe {
                private let queue = DispatchQueue(label: "connection-probe")
                private let monitor = NWPathMonitor()
                private var connection: NWConnection?

                func start(host: String) {
                    monitor.pathUpdateHandler = { path in
                        let interfaces = path.availableInterfaces.map { "\($0.name) (\($0.type))" }
                        print("Path: \(path.status), expensive: \(path.isExpensive), constrained: \(path.isConstrained), via \(interfaces)")
                    }
                    monitor.start(queue: queue)

                    let connection = NWConnection(host: NWEndpoint.Host(host), port: .https, using: .tls)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready: print("Connected")
                        case .waiting(let error): print("Waiting (no route or permission): \(error)")
                        case .failed(let error): print("Failed: \(error)")
                        default: print("State: \(state)")
                        }
                    }
                    connection.start(queue: queue)
                    self.connection = connection
                }

                func stop() {
                    connection?.cancel()
                    monitor.cancel()
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocalNetworkUsageDescription", value: "Connects to devices and services on your local network."),
                .init(key: "NSBonjourServices", value: "<array><string>_http._tcp</string></array>"),
            ],
            notes: [
                "Don't pre-flight reachability: start the connection and react to .waiting, which also covers a denied local network permission.",
                "Connections to local addresses, listeners and Bonjour browsing trigger the local network prompt; internet hosts don't.",
                "A cancelled NWPathMonitor or NWConnection can't be restarted; create a new one.",
            ]
        ),
        "wifi-capabilities": ImplementationGuide(
            snippet: #"""
            import CoreLocation
            import NetworkExtension

            /// Reads the current Wi-Fi network and joins a new one.
            @MainActor
            final class WiFiManager {
                private let locationManager = CLLocationManager()

                /// Needs location permission (or a configured VPN / hotspot) and the Access Wi-Fi Information entitlement.
                func currentNetwork() async -> (ssid: String, bssid: String)? {
                    locationManager.requestWhenInUseAuthorization()
                    guard let network = await NEHotspotNetwork.fetchCurrent() else { return nil }
                    return (network.ssid, network.bssid)
                }

                /// Shows the system join alert; needs the Hotspot entitlement.
                func join(ssid: String, passphrase: String) async throws {
                    let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
                    configuration.joinOnce = true // Forget the network when the app goes to the background.
                    try await NEHotspotConfigurationManager.shared.apply(configuration)
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocationWhenInUseUsageDescription", value: "Reads the name of the Wi-Fi network you're connected to."),
                .init(key: "NSLocalNetworkUsageDescription", value: "Checks which devices on your network are reachable."),
            ],
            entitlements: [
                "com.apple.developer.networking.wifi-info = true",
                "com.apple.developer.networking.HotspotConfiguration = true",
            ],
            capabilities: ["Access Wi-Fi Information", "Hotspot"],
            notes: [
                "fetchCurrent() returns nil unless the app has precise location, a VPN configuration or joined the network itself.",
                "iOS has no public Wi-Fi scanning; on macOS use CWWiFiClient.shared().interface()?.scanForNetworks(withName:) from CoreWLAN.",
                "Multicast Networking, Network Extensions and 5G Network Slicing need entitlements Apple must grant on request.",
            ]
        ),
    ]
}
