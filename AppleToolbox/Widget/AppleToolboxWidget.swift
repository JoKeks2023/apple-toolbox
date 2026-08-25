import SwiftUI
import WidgetKit

private struct ToolboxWidgetEntry: TimelineEntry {
    let date: Date
}

private struct ToolboxWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ToolboxWidgetEntry {
        ToolboxWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ToolboxWidgetEntry) -> Void) {
        completion(ToolboxWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ToolboxWidgetEntry>) -> Void) {
        let entry = ToolboxWidgetEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }
}

private struct ToolboxWidgetView: View {
    let entry: ToolboxWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Toolbox", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text("Explore native Apple APIs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Open the lab")
                .font(.caption.weight(.semibold))
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct AppleToolboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AppleToolboxWidget", provider: ToolboxWidgetProvider()) { entry in
            ToolboxWidgetView(entry: entry)
        }
        .configurationDisplayName("Apple Toolbox")
        .description("A quick entry point into the Apple technology lab.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
