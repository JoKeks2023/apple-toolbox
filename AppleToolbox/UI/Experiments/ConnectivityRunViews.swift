import SwiftUI

struct NetworkPathRunView: View {
    @StateObject private var network = NetworkExperimentService()

    var body: some View {
        Button(network.isMonitoring ? "Stop Network Monitor" : "Start Network Monitor") { network.isMonitoring ? network.stop() : network.start() }.buttonStyle(.borderedProminent)
            .experimentSession(network)
        NetworkInterfacesView(interfaces: network.interfaces)
        OutputView(text: network.output, isError: network.output.localizedCaseInsensitiveContains("not available"))
    }
}

struct WatchConnectivityRunView: View {
    @ObservedObject private var continuity = ContinuityExperimentService.shared

    var body: some View {
        LabeledContent("Session", value: continuity.activation)
        LabeledContent("Paired Apple Watch", value: continuity.isPaired.map { $0 ? "Yes" : "No" } ?? "—")
        LabeledContent("Watch app installed", value: continuity.isCounterpartInstalled.map { $0 ? "Yes" : "No" } ?? "—")
        LabeledContent("Reachable", value: continuity.isReachable ? "Yes" : "No")
        if let lastMessage = continuity.lastMessage { LabeledContent("Last message", value: lastMessage) }
        HStack {
            Button("Activate WatchConnectivity", action: continuity.activate).buttonStyle(.borderedProminent)
            Button("Ping Apple Watch", action: continuity.ping).buttonStyle(.bordered)
        }
        OutputView(text: continuity.output, isError: continuity.output.localizedCaseInsensitiveContains("error"))
    }
}

struct NearbyInteractionRunView: View {
    @StateObject private var nearby = NearbyExperimentService()

    var body: some View {
        Group {
            if nearby.isRunning {
                Button("Stop Nearby Interaction", action: nearby.stop).buttonStyle(.borderedProminent)
            } else {
                Button("Inspect Nearby Interaction", action: nearby.start).buttonStyle(.borderedProminent)
            }
        }
        .experimentSession(nearby)
        OutputView(text: nearby.output, isError: nearby.output.localizedCaseInsensitiveContains("error") || nearby.output.localizedCaseInsensitiveContains("not supported"))
    }
}

struct MultipeerRunView: View {
    @StateObject private var service = MultipeerConnectivityExperimentService()
    @State private var message = "Hello from Apple Toolbox"

    var body: some View {
        LabeledContent("Session", value: service.isRunning ? "Advertising and browsing" : "Stopped")
            .experimentSession(service)
        if service.isRunning {
            LabeledContent("Connected peers", value: service.connectedPeers.isEmpty ? "None yet" : service.connectedPeers.joined(separator: ", "))
            if !service.discoveredPeers.isEmpty {
                LabeledContent("Discovered peers", value: service.discoveredPeers.joined(separator: ", "))
            }
            TextField("Message to send", text: $message)
            HStack {
                Button("Send to connected peers") { service.send(message: message) }
                    .buttonStyle(.borderedProminent)
                Button("Stop", action: service.stop)
                    .buttonStyle(.bordered)
            }
        } else {
            Button("Discover nearby devices", action: service.start)
                .buttonStyle(.borderedProminent)
        }
        OutputView(text: service.output, isError: service.output.localizedCaseInsensitiveContains("could not") || service.output.localizedCaseInsensitiveContains("not supported") || service.output.localizedCaseInsensitiveContains("no connected"))
    }
}

private struct NetworkInterfacesView: View {
    let interfaces: [NetworkInterfaceResult]

    var body: some View {
        Section("Available interfaces") {
            if interfaces.isEmpty {
                Text("Start the monitor to inspect the current network path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(interfaces) { interface in
                    Label {
                        VStack(alignment: .leading) {
                            Text(interface.name)
                            Text(interface.type).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: interface.type.localizedCaseInsensitiveContains("wifi") ? "wifi" : "network")
                    }
                }
            }
        }
    }
}
