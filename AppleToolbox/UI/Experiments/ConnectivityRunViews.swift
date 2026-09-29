import SwiftUI

struct WatchConnectivityRunView: View {
    @ObservedObject private var continuity = ContinuityExperimentService.shared

    var body: some View {
        LabeledContent("Activation state", value: continuity.activation)
        LabeledContent("Paired Apple Watch (isPaired)", value: yesNo(continuity.isPaired))
        LabeledContent("Watch app installed", value: yesNo(continuity.isCounterpartInstalled))
        LabeledContent("Complication on active face", value: yesNo(continuity.isComplicationEnabled))
        LabeledContent("Complication transfers left today", value: continuity.remainingComplicationTransfers.map(String.init) ?? "—")
        LabeledContent("Reachable (live)", value: continuity.isReachable ? "Yes" : "No")
        if let lastMessage = continuity.lastMessage { LabeledContent("Last message", value: lastMessage) }
        HStack {
            Button("Activate", action: continuity.activate).buttonStyle(.borderedProminent)
            Button("Ping Apple Watch", action: continuity.ping).buttonStyle(.bordered)
        }
        OutputView(text: continuity.output, isError: continuity.output.localizedCaseInsensitiveContains("error") || continuity.output.localizedCaseInsensitiveContains("failed"))
        WatchTransfersSection(continuity: continuity)
        Text("The Apple Toolbox watch app runs independently (WKRunsIndependentlyOfCompanionApp): it can be installed from the watch without this iPhone app, and its experiments call the watch's own APIs. WatchConnectivity links the two only when both apps are installed. Open WatchConnectivity in the watch app to send in the other direction.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func yesNo(_ value: Bool?) -> String { value.map { $0 ? "Yes" : "No" } ?? "—" }
}

/// Application context, user info, file and complication transfers with their queues and what arrived.
private struct WatchTransfersSection: View {
    @ObservedObject var continuity: ContinuityExperimentService

    var body: some View {
        Section("Application context") {
            Button("Update Application Context", systemImage: "arrow.triangle.2.circlepath", action: continuity.updateContext)
            LabeledContent("Sent (applicationContext)", value: continuity.sentContext)
            LabeledContent("Received (receivedApplicationContext)", value: continuity.receivedContext)
        }
        Section("User info and files") {
            HStack {
                Button("Transfer User Info", action: continuity.sendUserInfo).buttonStyle(.bordered)
                Button("Transfer File", action: continuity.sendFile).buttonStyle(.bordered)
            }
            #if os(iOS)
            Button("Transfer Complication User Info", systemImage: "applewatch.watchface", action: continuity.sendComplicationInfo)
                .disabled(continuity.isComplicationEnabled != true)
            #endif
            HStack {
                Button("Refresh Queues", action: continuity.refreshTransfers)
                Button("Cancel Outstanding", role: .destructive, action: continuity.cancelOutstanding)
                    .disabled(continuity.outstandingUserInfo.isEmpty && continuity.outstandingFiles.isEmpty)
            }
            LabeledContent("Outstanding user info", value: "\(continuity.outstandingUserInfo.count)")
            ForEach(continuity.outstandingUserInfo) { row in LabeledContent(row.title, value: row.detail) }
            LabeledContent("Outstanding files", value: "\(continuity.outstandingFiles.count)")
            ForEach(continuity.outstandingFiles) { row in LabeledContent(row.title, value: row.detail) }
        }
        Section("Received from the watch") {
            if continuity.receivedUserInfo.isEmpty { Text("No user info received yet.").foregroundStyle(.secondary) }
            ForEach(continuity.receivedUserInfo) { row in LabeledContent(row.title, value: row.detail) }
            if let file = continuity.receivedFile {
                LabeledContent("File", value: "\(file.name) · \(file.byteCount) bytes")
                LabeledContent("Metadata", value: file.metadata)
                OutputView(text: file.preview, isError: false)
            }
        }
        if !continuity.transferLog.isEmpty {
            Section("Delivery log") {
                ForEach(continuity.transferLog) { row in LabeledContent(row.title, value: row.detail) }
            }
        }
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
