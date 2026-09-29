import SwiftUI

struct MetalRunView: View {
    #if canImport(Metal)
    @StateObject private var metal = MetalLabService()
    @State private var showsSource = false

    var body: some View {
        if metal.hasDevice {
            Button(metal.isRunning ? "Running…" : "Run Compute Check", systemImage: "cpu") { metal.runComputeCheck() }
                .buttonStyle(.borderedProminent)
                .disabled(metal.isRunning)
            ForEach(metal.facts) { LabeledContent($0.title, value: $0.value) }
            LabeledContent("GPU families", value: metal.families.isEmpty ? "None reported" : metal.families.joined(separator: ", "))
            if !metal.otherDevices.isEmpty {
                LabeledContent("Other GPUs", value: metal.otherDevices.joined(separator: ", "))
            }
            Toggle("Show kernel source", isOn: $showsSource)
            if showsSource {
                Text(MetalComputeCheck.kernelSource)
                    .font(.caption.monospaced())
                    .tvFocusableRow()
            }
        }
        OutputView(text: metal.output, isError: metal.isError)
    }
    #else
    var body: some View {
        OutputView(text: "Metal is not available on this platform.", isError: true)
    }
    #endif
}

struct MacHardwareRunView: View {
    #if os(macOS)
    @StateObject private var hardware = MacHardwareService()

    var body: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") { hardware.refresh(reason: nil) }
            Spacer()
            Toggle("Watch for changes", isOn: Binding(get: { hardware.isWatching }, set: { $0 ? hardware.startWatching() : hardware.stopWatching() }))
                .toggleStyle(.switch)
                .experimentSession(hardware)
        }
        OutputView(text: hardware.output, isError: false)
        Section("Audio devices · Core Audio") {
            if hardware.audioDevices.isEmpty { Text("Core Audio reports no devices.").foregroundStyle(.secondary) }
            ForEach(hardware.audioDevices) { AudioDeviceRow(device: $0) }
        }
        Section("Cameras · AVFoundation") {
            if hardware.cameras.isEmpty { Text("No camera is connected.").foregroundStyle(.secondary) }
            ForEach(hardware.cameras) { LabeledContent($0.title, value: $0.value) }
        }
        Section("Volumes · URL resource values") {
            ForEach(hardware.volumes) { FactGroupRow(title: $0.name, symbol: "internaldrive", facts: $0.facts) }
        }
        Section("Displays · NSScreen") {
            ForEach(hardware.displays) { FactGroupRow(title: $0.name, symbol: "display", facts: $0.facts) }
        }
    }
    #else
    var body: some View {
        OutputView(text: "Core Audio devices, mounted volumes and NSScreen are macOS APIs. Open Apple Toolbox on a Mac to inventory its hardware.", isError: true)
    }
    #endif
}

#if os(macOS)
private struct AudioDeviceRow: View {
    let device: AudioDeviceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(device.name, systemImage: device.inputChannels > 0 && device.outputChannels == 0 ? "mic" : "hifispeaker").font(.headline)
                Spacer()
                if device.isDefaultInput { InfoChip(title: "Default input", symbol: "mic.fill") }
                if device.isDefaultOutput { InfoChip(title: "Default output", symbol: "speaker.wave.2.fill") }
            }
            Text("\(device.manufacturer) · \(device.transport)").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Channels", value: "\(device.inputChannels) in · \(device.outputChannels) out")
            LabeledContent("Sample rate", value: device.sampleRate > 0 ? "\(MacHardwareFormatting.kilohertz(device.sampleRate)) kHz" : "Not reported")
            LabeledContent("Supported rates", value: device.availableRates)
        }
        .padding(.vertical, 4)
    }
}
#endif

/// A titled group of facts, used for volumes, displays and windows.
struct FactGroupRow: View {
    let title: String
    let symbol: String
    let facts: [PlatformFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            ForEach(facts) { LabeledContent($0.title, value: $0.value) }
        }
        .padding(.vertical, 4)
    }
}
