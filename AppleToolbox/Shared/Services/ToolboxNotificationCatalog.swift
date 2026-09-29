import Foundation

/// Notification categories registered by the app. Shared with the iOS notification content extension,
/// which draws the custom UI for `report` (its Info.plist lists the same identifier).
nonisolated enum ToolboxNotificationCategory: String, CaseIterable, Identifiable, Sendable {
    /// No category: the system only offers its default actions.
    case none = ""
    /// Text input, authentication-required, foreground and destructive actions, answered by the app's delegate.
    case actions = "toolbox.actions"
    /// Rendered by the notification content extension with a custom SwiftUI view.
    case report = "toolbox.report"

    var id: String { rawValue.isEmpty ? "none" : rawValue }

    var title: String {
        switch self {
        case .none: "No category"
        case .actions: "Actions"
        case .report: "Custom UI (content extension)"
        }
    }
}

/// Action identifiers of the registered categories.
nonisolated enum ToolboxNotificationAction {
    static let reply = "toolbox.action.reply"
    static let verify = "toolbox.action.verify"
    static let open = "toolbox.action.open"
    static let delete = "toolbox.action.delete"
    /// Handled inside the content extension, which keeps the notification open.
    static let acknowledge = "toolbox.action.acknowledge"

    /// Readable name for an action identifier, including the system's default and dismiss identifiers.
    static func title(for identifier: String, defaultIdentifier: String, dismissIdentifier: String) -> String {
        switch identifier {
        case defaultIdentifier: "Opened (default action)"
        case dismissIdentifier: "Dismissed (custom dismiss action)"
        case reply: "Reply (text input)"
        case verify: "Mark Verified (authentication required)"
        case open: "Open Experiment (foreground)"
        case delete: "Delete (destructive)"
        case acknowledge: "Acknowledge (content extension)"
        default: "Action \(identifier)"
        }
    }
}

/// The device report carried in the `userInfo` of `report` notifications and drawn by the content extension.
nonisolated struct ToolboxNotificationReport: Codable, Equatable, Sendable {
    nonisolated struct Bucket: Codable, Equatable, Sendable {
        let title: String
        let count: Int
    }

    static let userInfoKey = "toolbox.report"

    let platform: String
    let available: Int
    let total: Int
    /// Experiment count per status title, largest first.
    let buckets: [Bucket]
    let measuredAt: Date

    init(platform: String, statusTitles: [String], availableTitle: String, measuredAt: Date) {
        self.platform = platform
        self.available = statusTitles.filter { $0 == availableTitle }.count
        self.total = statusTitles.count
        self.buckets = Dictionary(grouping: statusTitles, by: { $0 })
            .map { Bucket(title: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.title < $1.title : $0.count > $1.count }
        self.measuredAt = measuredAt
    }

    /// `userInfo` must hold property-list values, so the report travels as a JSON string.
    var userInfo: [String: String] {
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else { return [:] }
        return [Self.userInfoKey: json]
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let json = userInfo[Self.userInfoKey] as? String,
              let report = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)) else { return nil }
        self = report
    }
}
