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
    var body: some View {
        NavigationStack {
            List {
                Section("Watch Lab") {
                    NavigationLink { WatchMotionView() } label: { Label("Motion", systemImage: "gyroscope") }
                    NavigationLink { WatchHapticsView() } label: { Label("Haptics", systemImage: "hand.tap") }
                    NavigationLink { WatchLinkView() } label: { Label("iPhone Link", systemImage: "iphone.radiowaves.left.and.right") }
                    NavigationLink { WatchDeviceView() } label: { Label("Device", systemImage: "applewatch") }
                }
                Section {
                    NavigationLink { WatchExperimentListView() } label: { Label("All Experiments", systemImage: "list.bullet") }
                } footer: {
                    Text("Status of every Apple Toolbox experiment on this watch.")
                }
            }
            .navigationTitle("Toolbox")
        }
    }
}

private struct WatchExperimentListView: View {
    var body: some View {
        List {
            ForEach(ExperimentCategory.allCases) { category in
                let experiments = ExperimentRegistry.all.filter { $0.category == category }
                if !experiments.isEmpty {
                    Section(category.rawValue) {
                        ForEach(experiments) { experiment in
                            NavigationLink { WatchExperimentDetailView(experiment: experiment) } label: { WatchExperimentRow(experiment: experiment) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Experiments")
    }
}

private struct WatchExperimentRow: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        let status = experiment.currentStatus
        VStack(alignment: .leading, spacing: 2) {
            Text(experiment.name)
            Text(status.title).font(.caption2.weight(.semibold)).foregroundStyle(status == .available ? .green : .orange)
        }
    }
}

private struct WatchExperimentDetailView: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        List {
            Section {
                Text(experiment.description).font(.caption)
                LabeledContent("Status", value: experiment.currentStatus.title)
                LabeledContent("Platforms", value: experiment.supportedPlatforms.map(\.rawValue).joined(separator: ", "))
            }
            switch experiment.id {
            case "core-motion": NavigationLink("Run on Watch") { WatchMotionView() }
            case "continuity": NavigationLink("Run on Watch") { WatchLinkView() }
            default: EmptyView()
            }
        }
        .navigationTitle(experiment.name)
    }
}
