import Foundation
import Combine
#if canImport(WidgetKit) && os(iOS)
import WidgetKit
import AppIntents
#endif

struct InstalledWidgetConfiguration: Identifiable {
    let id = UUID()
    let kind: String
    let family: String
}

/// One configuration the widget extension ships, with how many the person has placed.
struct WidgetKindRow: Identifiable {
    enum Reload { case timeline, control, none }

    let id: String
    let title: String
    let type: String
    let detail: String
    let placed: Int?
    let reload: Reload
}

/// The App Group state the interactive widget and the controls change, as display values.
struct WidgetSharedStateSummary: Equatable {
    var favorite: String?
    var refreshCount = 0
    var lastRefresh: Date?
    var interactions: [String] = []
}

/// The intents the run view can execute in the app's own process.
enum WidgetIntentRun: String, CaseIterable, Identifiable {
    case refresh, pin, unpin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refresh: "Refresh"
        case .pin: "Pin"
        case .unpin: "Unpin"
        }
    }
}

/// Lists the widgets and controls the user placed, reloads them, and shares the last opened experiment and the
/// interactive state with them (iOS only: the widget extension is embedded in the iOS app).
@MainActor
final class WidgetKitExperimentService: ObservableObject {
    @Published private(set) var output = "List the installed widgets and controls, or reload them."
    @Published private(set) var isError = false
    @Published private(set) var isLoading = false
    @Published private(set) var configurations: [InstalledWidgetConfiguration] = []
    @Published private(set) var controls: [InstalledWidgetConfiguration] = []
    @Published private(set) var sharedState = WidgetSharedStateSummary()
    @Published private(set) var runningIntent: WidgetIntentRun?

    /// Every widget, control and Live Activity in the extension's WidgetBundle, with the placed count once listed.
    var kinds: [WidgetKindRow] {
        #if canImport(WidgetKit) && os(iOS)
        ToolboxWidgetStore.kinds.map { info in
            let placed: Int? = switch info.kind {
            case .widget: configurations.filter { $0.kind == info.id }.count
            case .control: controls.filter { $0.kind == info.id }.count
            case .liveActivity: nil
            }
            let reload: WidgetKindRow.Reload = switch info.kind {
            case .widget: .timeline
            case .control: .control
            case .liveActivity: .none
            }
            return WidgetKindRow(id: info.id, title: info.title, type: info.kind.rawValue, detail: info.detail, placed: placed, reload: reload)
        }
        #else
        []
        #endif
    }

    func refresh() {
        #if canImport(WidgetKit) && os(iOS)
        isLoading = true
        loadSharedState()
        Task {
            defer { isLoading = false }
            let shared = Self.sharedDataReport()
            var lines = [shared]
            do {
                let infos = try await WidgetCenter.shared.currentConfigurations()
                configurations = infos.map { InstalledWidgetConfiguration(kind: $0.kind, family: $0.family.description) }
                lines.append("Placed widgets: \(infos.count)" + (infos.isEmpty ? " · add “Apple Toolbox” or “Toolbox Controls” from the widget gallery" : ""))
                isError = false
            } catch {
                configurations = []
                lines.append("WidgetCenter error: \(error.localizedDescription)")
                isError = true
            }
            do {
                let placed = try await ControlCenter.shared.currentControls()
                controls = placed.map { InstalledWidgetConfiguration(kind: $0.kind, family: "Control") }
                lines.append("Placed controls: \(placed.count)" + (placed.isEmpty ? " · add them in Control Center's edit mode, on the Lock Screen or to the Action button" : ""))
            } catch {
                controls = []
                lines.append("ControlCenter error: \(error.localizedDescription)")
                isError = true
            }
            output = lines.joined(separator: "\n")
        }
        #else
        output = "The widget extension is only embedded in the iOS app, so there are no widgets or controls to list on this platform."
        #endif
    }

    func reload(_ row: WidgetKindRow) {
        #if canImport(WidgetKit) && os(iOS)
        switch row.reload {
        case .timeline: WidgetCenter.shared.reloadTimelines(ofKind: row.id)
        case .control: ControlCenter.shared.reloadControls(ofKind: row.id)
        case .none: return
        }
        output = "Requested a reload of “\(row.id)” at \(Date().formatted(date: .omitted, time: .standard)). The system decides when it re-renders.\n\(Self.sharedDataReport())"
        isError = false
        #endif
    }

    func reloadAll() {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        output = "reloadAllTimelines() and reloadAllControls() requested at \(Date().formatted(date: .omitted, time: .standard))."
        isError = false
        #else
        output = "WidgetKit timelines are only available for the iOS widget extension."
        #endif
    }

    /// Runs the widget's own intent in the app process, so the interaction log shows "app" instead of "widget extension".
    func run(_ intent: WidgetIntentRun) {
        #if canImport(WidgetKit) && os(iOS)
        runningIntent = intent
        Task {
            defer { runningIntent = nil }
            do {
                switch intent {
                case .refresh: _ = try await RefreshWidgetStatusIntent().perform()
                case .pin: _ = try await SetFavoriteExperimentIntent(value: true).perform()
                case .unpin: _ = try await SetFavoriteExperimentIntent(value: false).perform()
                }
                output = "\(intent.title) intent performed in the app; the widget and the pin control were asked to reload."
                isError = false
            } catch {
                output = "\(intent.title) intent failed: \(error.localizedDescription)"
                isError = true
            }
            loadSharedState()
        }
        #endif
    }

    func loadSharedState() {
        #if canImport(WidgetKit) && os(iOS)
        let state = ToolboxWidgetStore.loadInteractive()
        sharedState = WidgetSharedStateSummary(
            favorite: state.favorite.map { "\($0.experimentName) · pinned \($0.pinnedAt.formatted(date: .omitted, time: .shortened))" },
            refreshCount: state.refreshCount, lastRefresh: state.lastRefresh,
            interactions: state.interactions.map { "\($0.date.formatted(date: .omitted, time: .standard))  \($0.intent) · \($0.process)" })
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
        WidgetCenter.shared.reloadTimelines(ofKind: ToolboxWidgetStore.interactiveWidgetKind)
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
