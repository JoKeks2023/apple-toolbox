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

/// App Group store shared by the iOS app (writer) and the widget extension (reader).
nonisolated enum ToolboxWidgetStore {
    static let appGroup = "group.com.jorisconrad.AppleToolbox"
    static let widgetKind = "AppleToolboxWidget"
    private static let snapshotKey = "widget.lastOpenedExperiment"

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
}
