import SwiftUI
import WidgetKit

nonisolated struct WatchComplicationEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WatchComplicationSnapshot?
    /// Whether the App Group container is provisioned; without it the watch app cannot share anything.
    let isShared: Bool

    static var current: WatchComplicationEntry {
        WatchComplicationEntry(date: .now, snapshot: WatchComplicationStore.load(), isShared: WatchComplicationStore.containerURL != nil)
    }

    static let placeholder = WatchComplicationEntry(
        date: .now,
        snapshot: WatchComplicationSnapshot(availableCount: 24, totalCount: 64, heartRate: 68, heartRateDate: .now, updatedAt: .now),
        isShared: true)
}

/// Nonisolated: WidgetKit may ask for entries off the main thread.
nonisolated struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchComplicationEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .current)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchComplicationEntry>) -> Void) {
        // The watch app reloads this timeline when it writes new data (foreground, heart rate, background refresh).
        completion(Timeline(entries: [.current], policy: .never))
    }
}

@main
struct AppleToolboxComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationStore.widgetKind, provider: WatchComplicationProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("Apple Toolbox")
        .description("Experiments available on this watch, the latest heart rate and the last iPhone ping.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

private struct WatchComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WatchComplicationSnapshot? { entry.snapshot }

    var body: some View {
        content.containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    private var circular: some View {
        Gauge(value: Double(snapshot?.availableCount ?? 0), in: 0...Double(max(snapshot?.totalCount ?? 1, 1))) {
            Image(systemName: "wrench.and.screwdriver")
        } currentValueLabel: {
            Text(snapshot.map { "\($0.availableCount)" } ?? "–")
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var inline: some View {
        ViewThatFits {
            Text(inlineText(long: true))
            Text(inlineText(long: false))
        }
    }

    private var corner: some View {
        Image(systemName: snapshot?.heartRate == nil ? "wrench.and.screwdriver" : "heart.fill")
            .font(.title3)
            .widgetLabel {
                Text(WatchComplicationStore.heartRateText(snapshot) ?? snapshot.map { "\($0.availableCount) of \($0.totalCount) available" } ?? "Open Toolbox")
            }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Apple Toolbox", systemImage: "wrench.and.screwdriver").font(.headline).widgetAccentable()
            if let snapshot {
                Text("\(snapshot.availableCount) of \(snapshot.totalCount) available")
                if let heartRate = WatchComplicationStore.heartRateText(snapshot) {
                    Text("♥︎ \(heartRate)").foregroundStyle(.secondary)
                } else if let ping = snapshot.lastPing {
                    Text(ping).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("\(snapshot.source) · \(snapshot.updatedAt, style: .time)").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(entry.isShared ? "Open the watch app once." : "App Group not provisioned.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineText(long: Bool) -> String {
        guard let snapshot else { return "Toolbox: open the app" }
        let count = "\(snapshot.availableCount)/\(snapshot.totalCount)"
        guard long, let heartRate = WatchComplicationStore.heartRateText(snapshot) else { return "Toolbox \(count)" }
        return "Toolbox \(count) · ♥︎ \(heartRate)"
    }
}
