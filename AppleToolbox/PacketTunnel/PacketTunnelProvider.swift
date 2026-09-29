import Foundation
import NetworkExtension

/// A harmless packet tunnel: there is no server and nothing leaves the device. The tunnel claims only the benchmarking
/// range 198.18.0.0/15 (no default route, no DNS settings), so normal traffic is untouched. It reads the packets the
/// system routes into it, counts them and drops them, and reports the counters to the app through `handleAppMessage`.
///
/// NetworkExtension calls the overrides on the provider's own queue and delivers packets on another one; the counters
/// are only touched under `lock`, which is why the class is `@unchecked Sendable`.
nonisolated final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var stats = TunnelStats()
    private var isReading = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping ((any Error)?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: TunnelTestRange.serverAddress)
        let ipv4 = NEIPv4Settings(addresses: [TunnelTestRange.interfaceAddress], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: TunnelTestRange.network, subnetMask: TunnelTestRange.subnetMask)]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        // NetworkExtension accepts the single completion call from any queue.
        nonisolated(unsafe) let completionHandler = completionHandler
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                completionHandler(error)
                return
            }
            self?.lock.withLock {
                self?.stats = TunnelStats(startedAt: Date())
                self?.isReading = true
            }
            self?.readPackets()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        lock.withLock { isReading = false }
        completionHandler()
    }

    /// Answers `stats` with the counters as JSON; `reset` clears them first.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let message = TunnelAppMessage(data: messageData)
        let snapshot = lock.withLock {
            if message == .reset { stats = TunnelStats(startedAt: stats.startedAt) }
            return stats
        }
        completionHandler?(snapshot.encoded)
    }

    /// Reads until the tunnel stops. The packets are not written anywhere: the test range has no destination.
    private func readPackets() {
        packetFlow.readPacketObjects { [weak self] packets in
            guard let self else { return }
            let keepReading = lock.withLock {
                let now = Date()
                for packet in packets { stats.record(packet.data, at: now) }
                return isReading
            }
            if keepReading { readPackets() }
        }
    }
}
