import SwiftUI

extension SpatialLinkService: StoppableExperiment { var isActive: Bool { isRunning } }

/// Spatial Link (spec §39): nearby Apple Toolbox devices over MultipeerConnectivity, UWB ranging between capable
/// iPhones, each device's network path, and the paired Apple Watch over WatchConnectivity.
struct SpatialLinkRunView: View {
    @StateObject private var link = SpatialLinkService()

    var body: some View {
        Button(link.isRunning ? "Stop Spatial Link" : "Start Spatial Link") { link.isRunning ? link.stop() : link.start() }
            .buttonStyle(.borderedProminent)
            .experimentSession(link)
        SpatialLinkThisDeviceSection(link: link)
        SpatialLinkPeersSection(link: link)
        #if os(iOS)
        SpatialLinkWatchSection()
        #endif
        Section("Log") {
            OutputView(text: NetworkLogFormatter.text(link.log, placeholder: "Start Spatial Link on two or more devices with Apple Toolbox open. Discovery, connections, UWB sessions and errors appear here."),
                       isError: link.log.last?.kind == .error)
        }
    }
}

private struct SpatialLinkThisDeviceSection: View {
    @ObservedObject var link: SpatialLinkService

    var body: some View {
        Section("This device") {
            LabeledContent("Name", value: link.localDevice.name)
            LabeledContent("Platform", value: link.localDevice.platform)
            LabeledContent("Ultra Wideband", value: link.localDevice.supportsUWB ? "Yes" : "No")
            LabeledContent("Network path", value: link.localPath?.summary ?? (link.isRunning ? "Waiting for NWPathMonitor…" : "—"))
        }
    }
}

private struct SpatialLinkPeersSection: View {
    @ObservedObject var link: SpatialLinkService

    var body: some View {
        Section("Nearby Apple Toolbox devices (\(link.peers.count))") {
            let blips = link.peers.filter { $0.distance != nil }.map { RadarBlip(id: $0.id, label: $0.name, distance: $0.distance, azimuth: $0.azimuth) }
            if !blips.isEmpty {
                NearbyRadarView(blips: blips, range: NearbyGeometry.radarRange(for: blips.compactMap(\.distance)))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            if link.peers.isEmpty {
                Label(link.isRunning ? "Searching for devices…" : "Not running", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
            ForEach(link.peers) { peer in
                SpatialLinkPeerRow(peer: peer)
            }
            Text("Transport shows what Apple Toolbox uses: MultipeerConnectivity always, UWB when both devices have an Ultra Wideband chip (iPhone 11 or later; iPad and Mac have none). MultipeerConnectivity does not reveal whether a session runs over infrastructure Wi-Fi, peer-to-peer Wi-Fi or Bluetooth. Latency is the round trip of a small reliable message; the network path is what each device's NWPathMonitor reports.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpatialLinkPeerRow: View {
    let peer: SpatialLinkPeer

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(peer.name, systemImage: symbol)
                    .font(.headline)
                Spacer()
                Text(peer.state.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(peer.state == .connected ? .green : .secondary)
            }
            HStack(spacing: 6) {
                ForEach(peer.transports, id: \.self) { InfoChip(title: $0, symbol: $0 == "UWB" ? "sensor.tag.radiowaves.forward" : "point.3.connected.trianglepath.dotted") }
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow { Text("Platform").foregroundStyle(.secondary); Text(peer.platform + (peer.system.map { " · \($0)" } ?? "")) }
                GridRow { Text("Distance").foregroundStyle(.secondary); Text(distanceText) }
                GridRow { Text("Direction").foregroundStyle(.secondary); Text(peer.azimuth.map(NearbyGeometry.degrees) ?? (peer.isRanging ? "Not available" : "—")) }
                GridRow { Text("Latency").foregroundStyle(.secondary); Text(peer.latencyMilliseconds.map { "\($0) ms round trip" } ?? "—") }
                GridRow { Text("Network").foregroundStyle(.secondary); Text(peer.networkPath ?? "—") }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var distanceText: String {
        if let distance = peer.distance { return NearbyGeometry.meters(distance) }
        if peer.isRanging { return "Waiting for UWB measurements" }
        switch peer.supportsUWB {
        case false: return "No UWB on the peer"
        default: return SpatialLinkService.localSupportsUWB ? "—" : "No UWB on this device"
        }
    }

    private var symbol: String {
        switch peer.platform {
        case "iPhone": "iphone"
        case "iPad": "ipad"
        case "Mac": "laptopcomputer"
        default: "questionmark.circle"
        }
    }
}

#if os(iOS)
private struct SpatialLinkWatchSection: View {
    @ObservedObject private var watch = ContinuityExperimentService.shared

    var body: some View {
        Section("Apple Watch · WatchConnectivity") {
            LabeledContent("Session", value: watch.activation)
            LabeledContent("Paired · app installed", value: "\(watch.isPaired.map { $0 ? "Yes" : "No" } ?? "—") · \(watch.isCounterpartInstalled.map { $0 ? "Yes" : "No" } ?? "—")")
            LabeledContent("Reachable", value: watch.isReachable ? "Yes" : "No")
            LabeledContent("Latency", value: watch.lastRoundTripMilliseconds.map { "\($0) ms round trip" } ?? "—")
            Text("watchOS has no MultipeerConnectivity, so the watch links to its paired iPhone only, through WatchConnectivity. While Spatial Link runs and the watch app is open, the iPhone pings it every two seconds. UWB ranging with an Apple Watch (Series 6 or later) runs in the Nearby Interaction experiment of the watch app, which swaps discovery tokens with this iPhone over WatchConnectivity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
