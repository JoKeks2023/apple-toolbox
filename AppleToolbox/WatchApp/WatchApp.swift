import SwiftUI

@main
struct AppleToolboxWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchHomeView() }
    }
}

private struct WatchHomeView: View {
    var body: some View {
        NavigationStack {
            List(ExperimentRegistry.all) { experiment in
                NavigationLink(experiment.name) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(experiment.name).font(.headline)
                        Text(experiment.description).font(.caption).foregroundStyle(.secondary)
                        Text(experiment.currentStatus.title).font(.caption2.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Toolbox")
        }
    }
}
