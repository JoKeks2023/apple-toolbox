import SwiftUI
import WatchKit
import WidgetKit

struct WatchMotionView: View {
    @StateObject private var motion = MotionExperimentService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section("Device motion") {
                Button(motion.isRunning ? "Stop" : "Start", systemImage: motion.isRunning ? "stop.fill" : "play.fill") {
                    motion.isRunning ? motion.stopMotion() : motion.startMotion()
                }
                WatchVectorRow(title: "Acceleration · g", vector: motion.userAcceleration)
                WatchVectorRow(title: "Rotation · rad/s", vector: motion.rotationRate)
                WatchVectorRow(title: "Gravity · g", vector: motion.gravity)
                WatchVectorRow(title: "Roll · pitch · yaw · °", vector: motion.attitude, digits: 0)
            }
            Section {
                Button(motion.isPedometerRunning ? "Stop Pedometer" : "Start Pedometer", systemImage: motion.isPedometerRunning ? "stop.fill" : "figure.walk") {
                    motion.isPedometerRunning ? motion.stopPedometer() : motion.startPedometer()
                }
                LabeledContent("Steps", value: motion.pedometerReading.steps)
                LabeledContent("Today", value: motion.pedometerReading.today)
                LabeledContent("Distance", value: motion.pedometerReading.distance)
                LabeledContent("Floors", value: motion.pedometerReading.floors)
                LabeledContent("Cadence", value: motion.pedometerReading.cadence)
                LabeledContent("Pace", value: motion.pedometerReading.pace)
            } header: {
                Text("Pedometer · CMPedometer")
            } footer: {
                Text("Counts from the moment you start; Today queries the pedometer history since midnight.")
            }
            Section {
                Button(motion.isAltimeterRunning ? "Stop Altimeter" : "Start Altimeter", systemImage: motion.isAltimeterRunning ? "stop.fill" : "barometer") {
                    motion.isAltimeterRunning ? motion.stopAltimeter() : motion.startAltimeter()
                }
                LabeledContent("Relative", value: motion.altitudeReading.relative)
                LabeledContent("Pressure", value: motion.altitudeReading.pressure)
                LabeledContent("Absolute", value: motion.altitudeReading.absolute)
                LabeledContent("Accuracy", value: motion.altitudeReading.absoluteAccuracy)
            } header: {
                Text("Altimeter · CMAltimeter")
            } footer: {
                Text("Relative altitude starts at 0 m. Pedometer and altimeter need Motion & Fitness access; the first start asks for it.")
            }
            Section("Sensors") {
                ForEach(motion.features) { feature in
                    LabeledContent(feature.title, value: feature.detail)
                }
            }
            WatchOutput(text: motion.output, isError: motion.output.localizedCaseInsensitiveContains("error") || motion.output.localizedCaseInsensitiveContains("denied"))
        }
        .navigationTitle("Motion")
        .onDisappear { motion.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { motion.stop() }
        }
    }
}

private struct WatchVectorRow: View {
    let title: String
    let vector: MotionVector
    var digits = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                axis("x", vector.x)
                axis("y", vector.y)
                axis("z", vector.z)
            }
        }
    }

    private func axis(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(digits)))).font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

struct WatchHapticsView: View {
    @State private var selection = WKHapticType.notification
    @State private var output = "Pick a haptic, then play it."

    var body: some View {
        List {
            Picker("Haptic", selection: $selection) {
                ForEach(WatchHaptics.all, id: \.self) { Text($0.title).tag($0) }
            }
            Text(selection.purpose).font(.caption2).foregroundStyle(.secondary)
            Button("Play", systemImage: "play.fill") { output = WatchHaptics.play(selection) }
            Text(output).font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("Haptics")
    }
}

struct WatchLinkView: View {
    @ObservedObject private var link = ContinuityExperimentService.shared

    var body: some View {
        List {
            Section {
                LabeledContent("Session", value: link.activation)
                LabeledContent("Reachable", value: link.isReachable ? "Yes" : "No")
                LabeledContent("iPhone app", value: link.isCounterpartInstalled.map { $0 ? "Installed" : "Missing" } ?? "—")
                if let lastMessage = link.lastMessage {
                    Text(lastMessage).font(.caption)
                }
            }
            Button("Ping iPhone", systemImage: "iphone.radiowaves.left.and.right", action: link.ping)
            if link.activation != "Activated" {
                Button("Activate Session", action: link.activate)
            }
            Text(link.output).font(.caption2).foregroundStyle(.secondary)
            Section {
                LabeledContent("Runs independently", value: WatchAppIndependence.isIndependent ? "Yes" : "No")
            } footer: {
                Text("WKRunsIndependentlyOfCompanionApp lets this watch app install and run without the iPhone app. WatchConnectivity still needs Apple Toolbox on the paired iPhone; “iPhone app” above is WCSession.isCompanionAppInstalled.")
            }
        }
        .navigationTitle("iPhone Link")
        // The complication shows the last message exchanged with the iPhone.
        .onChange(of: link.lastMessage) { _, message in
            if let message { WatchComplicationUpdater.recordPing(message) }
        }
    }
}

struct WatchDeviceView: View {
    @StateObject private var device = WatchDeviceService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            ForEach(device.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        LabeledContent(row.title, value: row.value)
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if let footer = section.footer { Text(footer) }
                }
            }
        }
        .navigationTitle("Device")
        .onAppear(perform: device.start)
        .onDisappear(perform: device.stop)
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? device.start() : device.stop()
        }
    }
}

struct WatchHeartRateView: View {
    @StateObject private var heart = WatchHeartRateService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Button(heart.isRunning ? "Stop" : "Start", systemImage: heart.isRunning ? "stop.fill" : "heart.fill") {
                heart.isRunning ? heart.stop() : heart.start()
            }
            .disabled(!heart.isHealthDataAvailable)
            if let latest = heart.latest {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(latest.beatsPerMinute.rounded())) BPM").font(.title2.monospacedDigit().weight(.semibold))
                    Text(latest.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                LabeledContent("Context", value: latest.context)
                LabeledContent("Source", value: latest.source)
            }
            LabeledContent("Samples", value: "\(heart.received)")
            Text(heart.output).font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("Heart Rate")
        .onDisappear { heart.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, heart.isRunning { heart.stop() }
        }
    }
}

struct WatchComplicationLabView: View {
    @State private var snapshot = WatchComplicationStore.load()
    @State private var output = "The complication reads what this app last wrote to the App Group."
    @State private var configurations: [String]?

    var body: some View {
        List {
            Section {
                LabeledContent("App Group", value: WatchComplicationStore.containerURL == nil ? "Not provisioned" : "Shared")
                if let snapshot {
                    LabeledContent("Experiments", value: "\(snapshot.availableCount) of \(snapshot.totalCount)")
                    LabeledContent("Heart rate", value: WatchComplicationStore.heartRateText(snapshot) ?? "—")
                    LabeledContent("Last ping", value: snapshot.lastPing ?? "—")
                    LabeledContent("Updated", value: "\(snapshot.source), \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    LabeledContent("Next refresh", value: snapshot.nextRefresh?.formatted(date: .omitted, time: .shortened) ?? "Not scheduled")
                }
                LabeledContent("On watch faces", value: configurations.map { $0.isEmpty ? "None" : $0.joined(separator: ", ") } ?? "Checking…")
            }
            Button("Update Now", systemImage: "arrow.clockwise") {
                WatchComplicationUpdater.record(source: "App")
                snapshot = WatchComplicationStore.load()
                output = "Wrote the snapshot and asked WidgetKit to reload the complication timeline."
            }
            Button("Schedule Refresh", systemImage: "clock.arrow.circlepath") {
                Task {
                    output = await WatchComplicationUpdater.scheduleNextRefresh()
                    snapshot = WatchComplicationStore.load()
                }
            }
            Text(output).font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("Complication")
        .task { await loadConfigurations() }
    }

    private func loadConfigurations() async {
        do {
            let infos = try await WidgetCenter.shared.currentConfigurations()
            configurations = infos.filter { $0.kind == WatchComplicationStore.widgetKind }.map { "\($0.family)" }
        } catch {
            configurations = ["Error: \(error.localizedDescription)"]
        }
    }
}
