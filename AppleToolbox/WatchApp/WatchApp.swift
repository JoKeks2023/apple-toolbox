import SwiftUI

@main
struct AppleToolboxWatchApp: App {
    init() {
        // Activate immediately so the iPhone can reach the watch app while it is open.
        ContinuityExperimentService.shared.activate()
    }

    var body: some Scene {
        WindowGroup { WatchHomeView() }
    }
}

private struct WatchHomeView: View {
    @ObservedObject private var link = ContinuityExperimentService.shared

    var body: some View {
        NavigationStack {
            List {
                Section("iPhone link") {
                    LabeledContent("Session", value: link.activation)
                    LabeledContent("Reachable", value: link.isReachable ? "Yes" : "No")
                    if let lastMessage = link.lastMessage {
                        Text(lastMessage).font(.caption)
                    }
                    Button("Ping iPhone", action: link.ping)
                    Text(link.output).font(.caption2).foregroundStyle(.secondary)
                }
                Section("Experiments") {
                    ForEach(ExperimentRegistry.all) { experiment in
                        NavigationLink(experiment.name) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(experiment.name).font(.headline)
                                Text(experiment.description).font(.caption).foregroundStyle(.secondary)
                                Text(experiment.currentStatus.title).font(.caption2.weight(.semibold))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Toolbox")
        }
    }
}
