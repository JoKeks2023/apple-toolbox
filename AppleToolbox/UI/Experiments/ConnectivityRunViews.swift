import SwiftUI

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
