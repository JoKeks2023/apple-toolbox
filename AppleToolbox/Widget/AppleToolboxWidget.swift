import SwiftUI
import WidgetKit

private struct ToolboxWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ToolboxWidgetSnapshot?
    /// Whether the App Group container is provisioned; without it the app cannot share anything.
    let isShared: Bool

    static var current: ToolboxWidgetEntry {
        ToolboxWidgetEntry(date: .now, snapshot: ToolboxWidgetStore.load(), isShared: ToolboxWidgetStore.containerURL != nil)
    }
}

private struct ToolboxWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ToolboxWidgetEntry {
        ToolboxWidgetEntry(date: .now, snapshot: nil, isShared: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ToolboxWidgetEntry) -> Void) {
        completion(.current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ToolboxWidgetEntry>) -> Void) {
        // The app reloads this timeline whenever it records a newly opened experiment.
        completion(Timeline(entries: [.current], policy: .never))
    }
}

private struct ToolboxWidgetView: View {
    let entry: ToolboxWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.containerBackground(for: .widget) {
            if family == .accessoryInline || family == .accessoryRectangular {
                Color.clear
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var emptyMessage: String {
        entry.isShared ? "Open an experiment in Apple Toolbox to see it here." : "The App Group is not provisioned, so the app cannot share data with this widget."
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Apple Toolbox", systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let snapshot = entry.snapshot {
                LastOpenedView(snapshot: snapshot)
            } else {
                Spacer(minLength: 0)
                Text(emptyMessage).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.availableCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("of \(snapshot.totalCount) experiments available on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    ProgressView(value: Double(snapshot.availableCount), total: Double(max(snapshot.totalCount, 1)))
                        .tint(.green)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Toolbox", systemImage: "wrench.and.screwdriver")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let snapshot = entry.snapshot {
                Text(snapshot.experimentName).font(.headline).lineLimit(1)
                Text("\(snapshot.status) · \(snapshot.availableCount)/\(snapshot.totalCount) available")
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                Text(entry.isShared ? "Open an experiment" : "App Group missing").font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var inline: some View {
        if let snapshot = entry.snapshot {
            Label("\(snapshot.experimentName) · \(snapshot.status)", systemImage: snapshot.symbolName)
        } else {
            Label(entry.isShared ? "Toolbox: open an experiment" : "Toolbox: App Group missing", systemImage: "wrench.and.screwdriver")
        }
    }
}

private struct LastOpenedView: View {
    let snapshot: ToolboxWidgetSnapshot

    var body: some View {
        Text("Last opened").font(.caption2).foregroundStyle(.secondary)
        Label(snapshot.experimentName, systemImage: snapshot.symbolName)
            .font(.headline)
            .lineLimit(2)
        Text(snapshot.status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(snapshot.isAvailable ? .green : .orange)
        Spacer(minLength: 0)
        Text("\(Text(snapshot.openedAt, style: .relative)) ago")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

@main
struct AppleToolboxWidgetBundle: WidgetBundle {
    var body: some Widget {
        AppleToolboxWidget()
        ToolboxLiveActivity()
    }
}

struct AppleToolboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ToolboxWidgetStore.widgetKind, provider: ToolboxWidgetProvider()) { entry in
            ToolboxWidgetView(entry: entry)
        }
        .configurationDisplayName("Apple Toolbox")
        .description("The experiment you opened last and how many experiments work on this device.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
