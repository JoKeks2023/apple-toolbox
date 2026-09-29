import SwiftUI
import WatchKit

struct WatchMotionView: View {
    @StateObject private var motion = MotionExperimentService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Button(motion.isRunning ? "Stop" : "Start", systemImage: motion.isRunning ? "stop.fill" : "play.fill") {
                motion.isRunning ? motion.stopMotion() : motion.startMotion()
            }
            WatchVectorRow(title: "Acceleration · g", vector: motion.userAcceleration)
            WatchVectorRow(title: "Rotation · rad/s", vector: motion.rotationRate)
            WatchVectorRow(title: "Gravity · g", vector: motion.gravity)
            Text(motion.output).font(.caption2).foregroundStyle(.secondary)
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
            Text(value.formatted(.number.precision(.fractionLength(2)))).font(.caption.monospacedDigit())
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
        }
        .navigationTitle("iPhone Link")
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
