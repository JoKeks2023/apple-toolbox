import Foundation

/// The experiment opened last in the app, as shown by the widget.
nonisolated struct ToolboxWidgetSnapshot: Codable, Equatable, Sendable {
    let experimentID: String
    let experimentName: String
    let symbolName: String
    let status: String
    let isAvailable: Bool
    let openedAt: Date
    let availableCount: Int
    let totalCount: Int
}

/// What the interactive widget and the Control Center controls change through App Intents. The intents run in
/// whichever process the system picks (usually the widget extension), so every change records that process.
nonisolated struct ToolboxInteractiveState: Codable, Equatable, Sendable {
    nonisolated struct Favorite: Codable, Equatable, Sendable {
        let experimentID: String
        let experimentName: String
        let symbolName: String
        let pinnedAt: Date
    }

    nonisolated struct Interaction: Codable, Equatable, Sendable {
        let date: Date
        let intent: String
        let process: String
    }

    static let interactionLimit = 10

    var favorite: Favorite?
    var refreshCount = 0
    var lastRefresh: Date?
    /// Newest first.
    var interactions: [Interaction] = []

    mutating func record(_ intent: String, bundleIdentifier: String?, at date: Date) {
        interactions.insert(Interaction(date: date, intent: intent, process: Self.processName(bundleIdentifier)), at: 0)
        interactions = Array(interactions.prefix(Self.interactionLimit))
    }

    /// Pins the last opened experiment, or unpins; pinning without a last opened experiment leaves nothing pinned.
    mutating func setFavorite(_ isOn: Bool, from snapshot: ToolboxWidgetSnapshot?, at date: Date) {
        favorite = isOn ? snapshot.map { Favorite(experimentID: $0.experimentID, experimentName: $0.experimentName, symbolName: $0.symbolName, pinnedAt: date) } : nil
    }

    static func processName(_ bundleIdentifier: String?) -> String {
        guard let bundleIdentifier else { return "unknown process" }
        if bundleIdentifier.hasSuffix(".widget") { return "widget extension" }
        if bundleIdentifier.hasSuffix(".ios") { return "app" }
        return bundleIdentifier
    }
}

/// One widget, control or Live Activity configuration the widget extension ships.
nonisolated struct ToolboxWidgetKindInfo: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: String, Sendable { case widget = "Widget", control = "Control", liveActivity = "Live Activity" }

    let id: String
    let title: String
    let kind: Kind
    let detail: String
}

/// App Group store shared by the iOS app and the widget extension.
nonisolated enum ToolboxWidgetStore {
    static let appGroup = ToolboxIdentifiers.appGroup
    static let widgetKind = "AppleToolboxWidget"
    static let interactiveWidgetKind = "AppleToolboxInteractiveWidget"
    static let openAppControlKind = "\(ToolboxIdentifiers.base).control.open"
    static let favoriteControlKind = "\(ToolboxIdentifiers.base).control.favorite"
    private static let snapshotKey = "widget.lastOpenedExperiment"
    private static let interactiveKey = "widget.interactiveState"

    /// Everything the widget extension's WidgetBundle contains.
    static let kinds: [ToolboxWidgetKindInfo] = [
        ToolboxWidgetKindInfo(id: widgetKind, title: "Apple Toolbox", kind: .widget, detail: "Last opened experiment · small, medium, Lock Screen rectangular and inline"),
        ToolboxWidgetKindInfo(id: interactiveWidgetKind, title: "Toolbox Controls", kind: .widget, detail: "Interactive: Button and Toggle run App Intents · small (StandBy), medium"),
        ToolboxWidgetKindInfo(id: openAppControlKind, title: "Open Apple Toolbox", kind: .control, detail: "ControlWidgetButton · opens the app on the WidgetKit experiment"),
        ToolboxWidgetKindInfo(id: favoriteControlKind, title: "Pin Last Experiment", kind: .control, detail: "ControlWidgetToggle · SetValueIntent in the App Group"),
        ToolboxWidgetKindInfo(id: "ToolboxActivityAttributes", title: "Measurement run", kind: .liveActivity, detail: "ActivityConfiguration · Lock Screen and Dynamic Island, started by the Live Activities experiment"),
    ]

    /// nil when the App Group entitlement is not provisioned for this process. `UserDefaults(suiteName:)` alone
    /// would still succeed in that case, but its data would not be shared with the other process.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    private static var defaults: UserDefaults? {
        containerURL == nil ? nil : UserDefaults(suiteName: appGroup)
    }

    static func load() -> ToolboxWidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ToolboxWidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: ToolboxWidgetSnapshot) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    static func loadInteractive() -> ToolboxInteractiveState {
        guard let data = defaults?.data(forKey: interactiveKey),
              let state = try? JSONDecoder().decode(ToolboxInteractiveState.self, from: data) else { return ToolboxInteractiveState() }
        return state
    }

    /// Reads, changes and writes the interactive state; nil when the App Group is not provisioned for this process.
    @discardableResult
    static func updateInteractive(_ change: (inout ToolboxInteractiveState) -> Void) -> ToolboxInteractiveState? {
        guard let defaults else { return nil }
        var state = loadInteractive()
        change(&state)
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        defaults.set(data, forKey: interactiveKey)
        return state
    }
}
