import SwiftUI

/// WidgetKit (spec §26): the widgets, interactive widget, Control Center controls and Live Activity the widget
/// extension ships, what the person placed, reloads, and the App Group state the widget's intents change.
struct WidgetKitRunView: View {
    @StateObject private var widgets = WidgetKitExperimentService()

    var body: some View {
        Section("Placed widgets and controls") {
            HStack {
                Button(widgets.isLoading ? "Loading…" : "List Widgets and Controls", action: widgets.refresh)
                    .buttonStyle(.borderedProminent)
                    .disabled(widgets.isLoading)
                Button("Reload All", action: widgets.reloadAll)
                    .buttonStyle(.bordered)
            }
            ForEach(widgets.configurations + widgets.controls) { configuration in
                LabeledContent(configuration.kind, value: configuration.family)
            }
            OutputView(text: widgets.output, isError: widgets.isError)
        }
        .onAppear(perform: widgets.loadSharedState)

        Section("Kinds in the widget extension") {
            if widgets.kinds.isEmpty {
                Text("The widget extension is only embedded in the iOS app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(widgets.kinds) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title).font(.headline)
                        Spacer()
                        Text(row.type).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(row.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(row.detail).font(.caption)
                    HStack {
                        if let placed = row.placed {
                            Text("Placed: \(placed)").font(.caption.monospacedDigit())
                        }
                        Spacer()
                        switch row.reload {
                        case .timeline: Button("Reload Timeline") { widgets.reload(row) }
                        case .control: Button("Reload Control") { widgets.reload(row) }
                        case .none: Text("Started by the Live Activities experiment").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }

        Section("Shared interactive state · App Group") {
            LabeledContent("Pinned experiment", value: widgets.sharedState.favorite ?? "none")
            LabeledContent("Refreshes", value: "\(widgets.sharedState.refreshCount)")
            if let lastRefresh = widgets.sharedState.lastRefresh {
                LabeledContent("Last refresh", value: lastRefresh.formatted(date: .omitted, time: .standard))
            }
            HStack {
                ForEach(WidgetIntentRun.allCases) { intent in
                    Button(widgets.runningIntent == intent ? "Running…" : intent.title) { widgets.run(intent) }
                        .disabled(widgets.runningIntent != nil)
                }
            }
            .buttonStyle(.bordered)
            ForEach(widgets.sharedState.interactions, id: \.self) { Text($0).font(.caption.monospaced()) }
            Button("Re-read Shared State", systemImage: "arrow.clockwise", action: widgets.loadSharedState)
            Text("The Toolbox Controls widget's refresh button and pin toggle, and the Pin control, run their App Intents in the widget extension's process and write to the App Group; the buttons above run the same intents in the app. Each entry names the process that ran it. In StandBy the small widget loses its background and may be drawn in the vibrant rendering mode; the medium widget prints the mode it received.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
