import SwiftUI

struct DeveloperToolsLabRunView: View {
    @State private var kind: DeveloperToolEntry.Kind?

    var body: some View {
        Picker("Show", selection: $kind) {
            Text("All tools").tag(DeveloperToolEntry.Kind?.none)
            ForEach(DeveloperToolEntry.Kind.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
        ForEach(DeveloperToolsCatalog.all.filter { kind == nil || $0.kind == kind }) { tool in
            #if os(tvOS)
            // tvOS has no DisclosureGroup; show the details inline.
            VStack(alignment: .leading, spacing: 6) {
                ToolTitle(tool: tool)
                ToolDetails(tool: tool)
            }
            #else
            DisclosureGroup {
                ToolDetails(tool: tool)
            } label: {
                ToolTitle(tool: tool)
            }
            #endif
        }
    }
}

private struct ToolTitle: View {
    let tool: DeveloperToolEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tool.name).font(.headline)
            Text(tool.kind.rawValue).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ToolDetails: View {
    let tool: DeveloperToolEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tool.summary)
            Label(tool.inToolbox, systemImage: "wrench.and.screwdriver")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(tool.relatedExperiments, id: \.self) { id in
                if let experiment = ExperimentRegistry.descriptor(for: id) {
                    NavigationLink(value: id) { Label("Open \(experiment.name)", systemImage: "arrow.forward.circle") }
                }
            }
            if let documentation = tool.documentation {
                Link(destination: documentation) { Label("Documentation", systemImage: "book.closed") }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DiagnosticsRunView: View {
    @StateObject private var diagnostics = DiagnosticsExperimentService()
    @State private var level = DiagnosticLogLevel.notice
    @State private var minutes = 15

    var body: some View {
        Section("System") {
            ForEach(diagnostics.systemRows, id: \.0) { row in
                LabeledContent(row.0) { Text(row.1).multilineTextAlignment(.trailing) }
            }
        }
        .experimentSession(diagnostics)
        Section("Unified log (Console)") {
            Picker("Entry level", selection: $level) {
                ForEach(DiagnosticLogLevel.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Write Test Entry") { diagnostics.writeTestEntries(level: level) }
            Picker("Time window", selection: $minutes) {
                ForEach([5, 15, 60, 240], id: \.self) { Text("Last \($0) min").tag($0) }
            }
            Button(diagnostics.isLoadingLogs ? "Reading…" : "Load This App's Log") { Task { await diagnostics.loadLogs(minutes: minutes) } }
                .buttonStyle(.borderedProminent)
                .disabled(diagnostics.isLoadingLogs)
            ForEach(diagnostics.logLines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(line.date.formatted(date: .omitted, time: .standard)) · \(line.level) · \(line.category)")
                        .font(.caption.monospaced())
                        .foregroundStyle(line.level == "Error" || line.level == "Fault" ? .red : .secondary)
                    Text(line.message).font(.caption)
                }
            }
        }
        Section("Signposts (Instruments)") {
            Button("Measure a Workload") { diagnostics.measureSignpost() }
            if let result = diagnostics.signpostResult { Text(result).font(.callout) }
        }
        Section("MetricKit (Organizer)") {
            Button("Subscribe and Load Past Payloads", action: diagnostics.subscribeToMetrics)
            LabeledContent("State", value: diagnostics.metricKitState)
            ForEach(diagnostics.metricPayloads, id: \.self) { Text($0).font(.caption) }
        }
        OutputView(text: diagnostics.output, isError: diagnostics.output.localizedCaseInsensitiveContains("error"))
    }
}
