import Foundation

/// What the watch complication shows, written by the watch app and read by the watch widget extension.
nonisolated struct WatchComplicationSnapshot: Codable, Equatable, Sendable {
    var availableCount = 0
    var totalCount = 0
    var heartRate: Double?
    var heartRateDate: Date?
    var lastPing: String?
    var lastPingDate: Date?
    var updatedAt = Date.distantPast
    /// "App", "Background refresh", "Heart rate", "iPhone link".
    var source = "App"
    var nextRefresh: Date?
}

/// App Group store shared by the watch app (writer) and its widget extension (reader).
nonisolated enum WatchComplicationStore {
    static let appGroup = ToolboxIdentifiers.appGroup
    static let widgetKind = "AppleToolboxWatchComplication"
    /// Passed as `userInfo` when scheduling, so SwiftUI routes the task to `.backgroundTask(.appRefresh(_:))`.
    static let refreshIdentifier = "\(ToolboxIdentifiers.base).watch.complication-refresh"
    private static let snapshotKey = "watch.complication"

    /// nil when the App Group is not provisioned for this process; `UserDefaults(suiteName:)` would still succeed
    /// but would not share anything with the other process.
    static let containerURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)

    private static var defaults: UserDefaults? {
        containerURL == nil ? nil : UserDefaults(suiteName: appGroup)
    }

    static func load() -> WatchComplicationSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WatchComplicationSnapshot.self, from: data)
    }

    /// Loads, changes and saves the snapshot; false when the App Group is unavailable.
    @discardableResult
    static func update(_ change: (inout WatchComplicationSnapshot) -> Void) -> Bool {
        guard let defaults else { return false }
        var snapshot = load() ?? WatchComplicationSnapshot()
        change(&snapshot)
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    /// "72 BPM" for the complication; nil when there is no reading.
    static func heartRateText(_ snapshot: WatchComplicationSnapshot?) -> String? {
        guard let rate = snapshot?.heartRate else { return nil }
        return "\(Int(rate.rounded())) BPM"
    }
}
