import SwiftUI
import WidgetKit
import AppIntents

nonisolated struct ToolboxInteractiveEntry: TimelineEntry {
    let date: Date
    let state: ToolboxInteractiveState
    let snapshot: ToolboxWidgetSnapshot?
    let isShared: Bool

    static var current: ToolboxInteractiveEntry {
        ToolboxInteractiveEntry(date: .now, state: ToolboxWidgetStore.loadInteractive(), snapshot: ToolboxWidgetStore.load(),
                                isShared: ToolboxWidgetStore.containerURL != nil)
    }
}

/// Nonisolated: WidgetKit may call the provider off the main thread.
nonisolated struct ToolboxInteractiveProvider: TimelineProvider {
    func placeholder(in context: Context) -> ToolboxInteractiveEntry {
        ToolboxInteractiveEntry(date: .now, state: ToolboxInteractiveState(), snapshot: nil, isShared: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ToolboxInteractiveEntry) -> Void) {
        completion(.current)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ToolboxInteractiveEntry>) -> Void) {
        // The intents change the store and reload this timeline, so no refresh schedule is needed.
        completion(Timeline(entries: [.current], policy: .never))
    }
}

/// Interactive widget (iOS 17+): its Button and Toggle run App Intents in the widget extension's process,
/// which update the App Group store shared with the app.
struct ToolboxInteractiveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ToolboxWidgetStore.interactiveWidgetKind, provider: ToolboxInteractiveProvider()) { entry in
            ToolboxInteractiveWidgetView(entry: entry)
        }
        .configurationDisplayName("Toolbox Controls")
        .description("Refresh and pin the last opened experiment right in the widget. Works in StandBy.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ToolboxInteractiveWidgetView: View {
    let entry: ToolboxInteractiveEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    /// False in StandBy and wherever the system removes the background; the content then sits on black.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var isPinned: Bool { entry.state.favorite != nil }
    private var isFullColor: Bool { renderingMode == .fullColor }
    private var primary: Color { showsBackground && isFullColor ? .white : .primary }
    private var accent: Color { isFullColor ? (showsBackground ? .white : .teal) : .primary }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 14) {
                    controls
                    interactionLog
                }
            } else {
                controls
            }
        }
        .foregroundStyle(primary)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Toolbox", systemImage: "wrench.and.screwdriver")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .widgetAccentable()
            if let favorite = entry.state.favorite {
                Label(favorite.experimentName, systemImage: favorite.symbolName)
                    .font(.headline)
                    .lineLimit(2)
            } else if let snapshot = entry.snapshot {
                Text(snapshot.experimentName).font(.headline).lineLimit(2)
            } else {
                Text(entry.isShared ? "Open an experiment in the app" : "App Group missing").font(.caption)
            }
            Text("\(entry.state.refreshCount) refreshes").font(.caption2).opacity(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(intent: RefreshWidgetStatusIntent()) {
                    Image(systemName: "arrow.clockwise")
                }
                Toggle(isOn: isPinned, intent: SetFavoriteExperimentIntent(value: !isPinned)) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .disabled(!isPinned && entry.snapshot == nil)
            }
            .font(.body.weight(.semibold))
            .tint(accent)
            .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var interactionLog: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last intents").font(.caption.weight(.semibold)).opacity(0.8)
            if entry.state.interactions.isEmpty {
                Text("Tap refresh or the pin.").font(.caption2)
            }
            ForEach(Array(entry.state.interactions.prefix(3).enumerated()), id: \.offset) { _, interaction in
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(interaction.intent) · \(interaction.date.formatted(date: .omitted, time: .standard))").font(.caption2.weight(.medium))
                    Text("ran in the \(interaction.process)").font(.caption2).opacity(0.75)
                }
            }
            Spacer(minLength: 0)
            Text("\(String(describing: renderingMode)) · background \(showsBackground ? "shown" : "removed")")
                .font(.system(size: 9, design: .monospaced))
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
