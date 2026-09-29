import SwiftUI

@main
struct AppleToolboxWatchApp: App {
    init() {
        // Activate immediately so the iPhone can reach the watch app while it is open.
        ContinuityExperimentService.shared.activate()
        // Installed at launch so notifications show while the app is open and action responses reach the delegate log.
        ToolboxNotificationDelegate.install()
    }

    var body: some Scene {
        WindowGroup { WatchHomeView() }
            // Scheduled by WatchComplicationUpdater with this identifier as userInfo.
            .backgroundTask(.appRefresh(WatchComplicationStore.refreshIdentifier)) {
                await WatchComplicationUpdater.handleBackgroundRefresh()
            }
    }
}

private struct WatchHomeView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Watch Lab") {
                    NavigationLink { WatchMotionView() } label: { Label("Motion", systemImage: "gyroscope") }
                    NavigationLink { WatchHapticsView() } label: { Label("Haptics", systemImage: "hand.tap") }
                    NavigationLink { WatchLinkView() } label: { Label("iPhone Link", systemImage: "iphone.radiowaves.left.and.right") }
                    NavigationLink { WatchDeviceView() } label: { Label("Device", systemImage: "applewatch") }
                    NavigationLink { WatchHeartRateView() } label: { Label("Heart Rate", systemImage: "heart.fill") }
                    NavigationLink { WatchComplicationLabView() } label: { Label("Complication", systemImage: "applewatch.watchface") }
                }
                Section {
                    NavigationLink { WatchExperimentListView() } label: { Label("All Experiments", systemImage: "list.bullet") }
                } footer: {
                    Text("Status, checks and a watch run for every experiment that supports Apple Watch.")
                }
                Section {
                    Text(WatchAppIndependence.summary).font(.caption2).foregroundStyle(.secondary)
                } header: {
                    Text("Independent App")
                }
            }
            .navigationTitle("Toolbox")
        }
        // Keep the complication current whenever the app becomes active, and keep a background refresh pending.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            WatchComplicationUpdater.record(source: "App")
            Task { await WatchComplicationUpdater.scheduleNextRefresh() }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(experiment.name)
            HStack(spacing: 4) {
                WatchStatusText(status: experiment.currentStatus)
                if WatchRunCatalog.hasWatchRun(experiment.id) {
                    Image(systemName: "applewatch").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Runs on Apple Watch")
                }
            }
        }
    }
}

/// `WKRunsIndependentlyOfCompanionApp` (Info.plist, set through the target's build settings).
enum WatchAppIndependence {
    static var isIndependent: Bool {
        Bundle.main.object(forInfoDictionaryKey: "WKRunsIndependentlyOfCompanionApp") as? Bool ?? false
    }

    static var summary: String {
        isIndependent
            ? "WKRunsIndependentlyOfCompanionApp is YES: this watch app installs and runs without Apple Toolbox on the iPhone. Experiments on the watch call the watch's own APIs; only WatchConnectivity and UWB ranging with the iPhone need the iPhone app."
            : "WKRunsIndependentlyOfCompanionApp is not set, so watchOS treats this app as dependent on its iPhone app."
    }
}

