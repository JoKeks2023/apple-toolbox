import Foundation
import Combine

/// System entry points the app handled in this session (Spotlight results, Siri donations, Handoff, SharePlay), newest first.
/// The system reports these only as callbacks, so the run views show the app's own record of them.
@MainActor
final class ToolboxActivityLog: ObservableObject {
    enum Channel: String, Sendable {
        case spotlight = "Spotlight"
        case siri = "Siri"
        case handoff = "Handoff"
        case sharePlay = "SharePlay"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let channel: Channel
        let title: String
        let detail: String
    }

    static let shared = ToolboxActivityLog()
    private static let limit = 50

    @Published private(set) var entries: [Entry] = []

    func record(_ channel: Channel, _ title: String, _ detail: String = "") {
        entries.insert(Entry(channel: channel, title: title, detail: detail), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    func entries(in channels: Set<Channel>) -> [Entry] {
        entries.filter { channels.contains($0.channel) }
    }
}
