import Foundation
#if canImport(AppIntents) && os(iOS)
import AppIntents
import WidgetKit

/// App Intents behind the interactive widget and the Control Center controls. Compiled into the iOS app and the
/// widget extension: the system runs them in the widget's process when tapped there, and in the app when it runs
/// them in the foreground or when the WidgetKit experiment calls perform() itself.

/// Set by the app at launch; nil in the widget extension, which cannot navigate the app.
@MainActor
enum ToolboxWidgetIntentHost {
    static var openExperiment: ((String) -> Void)?
}

nonisolated enum ToolboxWidgetIntentError: Error, LocalizedError {
    case appGroupMissing

    var errorDescription: String? {
        "The App Group \(ToolboxWidgetStore.appGroup) is not provisioned for this process, so the shared state cannot change."
    }
}

struct RefreshWidgetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Apple Toolbox Widget"
    static let description = IntentDescription("Counts a refresh in the App Group store that the app and its widget share.")

    @MainActor func perform() async throws -> some IntentResult {
        let now = Date()
        guard ToolboxWidgetStore.updateInteractive({ state in
            state.refreshCount += 1
            state.lastRefresh = now
            state.record("Refresh", bundleIdentifier: Bundle.main.bundleIdentifier, at: now)
        }) != nil else { throw ToolboxWidgetIntentError.appGroupMissing }
        // WidgetKit reloads the widget that ran the intent; reload the others so every surface shows the same state.
        WidgetCenter.shared.reloadTimelines(ofKind: ToolboxWidgetStore.interactiveWidgetKind)
        return .result()
    }
}

/// Pins or unpins the experiment opened last. Drives the widget's Toggle and the Control Center toggle.
struct SetFavoriteExperimentIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Pin Last Opened Experiment"
    static let description = IntentDescription("Pins the experiment you opened last in Apple Toolbox, or unpins it.")

    @Parameter(title: "Pinned")
    var value: Bool

    init() {}
    init(value: Bool) { self.value = value }

    @MainActor func perform() async throws -> some IntentResult {
        let now = Date()
        let snapshot = ToolboxWidgetStore.load()
        let isOn = value
        guard ToolboxWidgetStore.updateInteractive({ state in
            state.setFavorite(isOn, from: snapshot, at: now)
            state.record(isOn ? "Pin" : "Unpin", bundleIdentifier: Bundle.main.bundleIdentifier, at: now)
        }) != nil else { throw ToolboxWidgetIntentError.appGroupMissing }
        WidgetCenter.shared.reloadTimelines(ofKind: ToolboxWidgetStore.interactiveWidgetKind)
        ControlCenter.shared.reloadControls(ofKind: ToolboxWidgetStore.favoriteControlKind)
        return .result()
    }
}

/// Opens the app on the WidgetKit experiment; `.foreground` makes the system launch the app and run it there.
struct OpenWidgetKitExperimentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open WidgetKit Experiment"
    static let description = IntentDescription("Opens Apple Toolbox on the WidgetKit experiment.")
    static let supportedModes: IntentModes = .foreground

    @MainActor func perform() async throws -> some IntentResult {
        let now = Date()
        ToolboxWidgetStore.updateInteractive { $0.record("Open app", bundleIdentifier: Bundle.main.bundleIdentifier, at: now) }
        ToolboxWidgetIntentHost.openExperiment?("widgetkit")
        return .result()
    }
}
#endif
