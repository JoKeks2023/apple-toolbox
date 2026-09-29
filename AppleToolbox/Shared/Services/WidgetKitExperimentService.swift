import Foundation
import Combine
#if canImport(WidgetKit) && os(iOS)
import WidgetKit
#endif

struct InstalledWidgetConfiguration: Identifiable {
    let id = UUID()
    let kind: String
    let family: String
}

/// Lists the widgets the user placed and shares the last opened experiment with them (iOS only:
/// the widget extension is embedded in the iOS app).
@MainActor
final class WidgetKitExperimentService: ObservableObject {
    @Published private(set) var output = "List the installed widgets or reload their timelines."
    @Published private(set) var isError = false
    @Published private(set) var isLoading = false
    @Published private(set) var configurations: [InstalledWidgetConfiguration] = []

    func refresh() {
        #if canImport(WidgetKit) && os(iOS)
        isLoading = true
        Task {
            defer { isLoading = false }
            let shared = Self.sharedDataReport()
            do {
                let infos = try await WidgetCenter.shared.currentConfigurations()
                configurations = infos.map { InstalledWidgetConfiguration(kind: $0.kind, family: $0.family.description) }
                output = "\(shared)\nInstalled configurations: \(infos.count)" + (infos.isEmpty ? "\nAdd “Apple Toolbox” from the Home Screen or Lock Screen widget gallery." : "")
                isError = false
            } catch {
                configurations = []
                output = "\(shared)\nWidgetCenter error: \(error.localizedDescription)"
                isError = true
            }
        }
        #else
        output = "The widget extension is only embedded in the iOS app, so there are no widgets to list on this platform."
        #endif
    }

    func reloadTimelines() {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: ToolboxWidgetStore.widgetKind)
        output = "Requested a timeline reload for kind “\(ToolboxWidgetStore.widgetKind)” at \(Date().formatted(date: .omitted, time: .standard)). WidgetKit decides when the widget re-renders.\n\(Self.sharedDataReport())"
        isError = false
        #else
        output = "WidgetKit timelines are only available for the iOS widget extension."
        #endif
    }

    /// Records the opened experiment for the widget and asks WidgetKit to reload it.
    static func recordOpened(_ experiment: ExperimentDescriptor) {
        #if canImport(WidgetKit) && os(iOS)
        let status = experiment.currentStatus
        let statuses = ExperimentRegistry.all.map(\.currentStatus)
        let snapshot = ToolboxWidgetSnapshot(experimentID: experiment.id, experimentName: experiment.name, symbolName: experiment.category.symbolName,
                                             status: status.title, isAvailable: status == .available, openedAt: Date(),
                                             availableCount: statuses.filter { $0 == .available }.count, totalCount: statuses.count)
        guard ToolboxWidgetStore.save(snapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: ToolboxWidgetStore.widgetKind)
        #endif
    }

    #if canImport(WidgetKit) && os(iOS)
    private static func sharedDataReport() -> String {
        guard ToolboxWidgetStore.containerURL != nil else {
            return "App Group \(ToolboxWidgetStore.appGroup) is not provisioned, so the widget cannot read data from the app."
        }
        guard let snapshot = ToolboxWidgetStore.load() else {
            return "App Group container available. Nothing shared yet; the widget shows its empty state."
        }
        return "Shared with the widget: \(snapshot.experimentName) · \(snapshot.status) · opened \(snapshot.openedAt.formatted(date: .omitted, time: .shortened))\n\(snapshot.availableCount) of \(snapshot.totalCount) experiments available at that time"
    }
    #endif
}

extension ExperimentAvailability {
    /// The widget can only show live data when the App Group container is provisioned for the app.
    static func widgetKit() -> ExperimentStatus {
        #if canImport(WidgetKit) && os(iOS)
        ToolboxWidgetStore.containerURL == nil ? .entitlementRequired : .available
        #else
        .platformUnsupported
        #endif
    }
}
