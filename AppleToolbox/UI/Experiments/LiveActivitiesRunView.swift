import SwiftUI

extension LiveActivityExperimentService: StoppableExperiment {}

/// Live Activities (spec §26): start, update and end a real ActivityKit activity drawn by the widget extension
/// on the Lock Screen and in the Dynamic Island.
struct LiveActivitiesRunView: View {
    @StateObject private var service = LiveActivityExperimentService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section("Authorization") {
            LabeledContent("areActivitiesEnabled", value: service.areActivitiesEnabled.map { $0 ? "true" : "false" } ?? "not read")
            LabeledContent("frequentPushesEnabled", value: service.frequentPushesEnabled.map { $0 ? "true" : "false" } ?? "not read")
            LabeledContent("NSSupportsLiveActivities", value: service.supportsLiveActivitiesKey)
            if service.areActivitiesEnabled == false {
                Text("false means Live Activities are switched off for Apple Toolbox in Settings, or this device cannot show them. ActivityKit does not say which.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: service.refresh)
        .onChange(of: scenePhase) { if scenePhase == .active { service.refresh() } }

        Section("Measurement run") {
            Picker("Run length", selection: $service.runLength) {
                ForEach(LiveActivityRunLength.allCases) { Text($0.title).tag($0) }
            }
            .disabled(service.currentID != nil)
            Picker("Dismissal after end", selection: $service.dismissal) {
                ForEach(LiveActivityDismissalChoice.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Update every \(LiveActivityRunLength.sampleInterval) s while the app runs", isOn: $service.autoUpdate)
            if service.currentID == nil {
                Button("Start Live Activity", systemImage: "play.fill", action: service.start)
                    .buttonStyle(.borderedProminent)
                    .experimentSession(service)
            } else {
                ProgressView(value: Double(service.sample), total: Double(max(service.totalSamples, 1))) {
                    Text("Sample \(service.sample) of \(service.totalSamples)")
                }
                HStack {
                    Button("Update Now") { service.updateNow(alert: false) }
                    Button("Update with Alert") { service.updateNow(alert: true) }
                }
                .buttonStyle(.bordered)
                Button("End Live Activity", systemImage: "stop.fill", role: .destructive, action: service.end)
                    .buttonStyle(.borderedProminent)
            }
            OutputView(text: service.output, isError: service.isError)
            Text("Each sample carries real values: battery level and state (UIDevice), thermal state and Low Power Mode (ProcessInfo). When the app is suspended it stops updating, and after \(LiveActivityRunLength.staleAfter) s without an update the system marks the activity stale. Updating it while the app is not running needs ActivityKit push notifications (pushType .token) sent from a server; this experiment requests with pushType nil.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("activityStateUpdates (\(service.stateLog.count))") {
            if service.stateLog.isEmpty {
                Text("State changes of the running activity appear here: active, stale, ended, dismissed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(service.stateLog, id: \.self) { Text($0).font(.caption.monospaced()) }
        }

        Section("Activities of this app (\(service.activities.count))") {
            ForEach(service.activities) { activity in
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.id).font(.caption.monospaced())
                    Text("\(activity.state) · \(activity.detail)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise", action: service.refresh)
                if !service.activities.isEmpty {
                    Spacer()
                    Button("End All", role: .destructive, action: service.endAll)
                }
            }
            .buttonStyle(.borderless)
            Text("The widget extension draws the activity: a Lock Screen banner with a live timer and progress, and the Dynamic Island in its compact, minimal and expanded presentations (long-press the island to expand it).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
