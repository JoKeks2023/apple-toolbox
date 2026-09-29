import SwiftUI

struct GameControllerRunView: View {
    #if canImport(GameController) && !os(watchOS)
    @StateObject private var service = GameControllerExperimentService()

    var body: some View {
        Button(service.isMonitoring ? "Stop Monitoring" : "Start Monitoring") { service.isMonitoring ? service.stop() : service.start() }
            .buttonStyle(.borderedProminent)
            .experimentSession(service)
        Button(service.isDiscovering ? "Stop Wireless Discovery" : "Discover Wireless Controllers") {
            service.isDiscovering ? service.stopDiscovery() : service.startDiscovery()
        }
        if service.controllers.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("No controller connected", systemImage: "gamecontroller").font(.headline)
                Text("Pair an MFi, Xbox, PlayStation, or Switch controller in Bluetooth settings, or put an MFi controller in pairing mode and discover it here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ForEach(service.controllers) { ControllerInfoRow(controller: $0) }
        }
        if let input = service.input { ControllerInputView(input: input) }
        OutputView(text: service.output, isError: false)
        #if os(tvOS)
        Text("The Siri Remote and controllers also move focus while you test. Menu or B leaves this screen and stops monitoring.")
            .font(.caption).foregroundStyle(.secondary)
        #endif
    }
    #else
    var body: some View {
        OutputView(text: "The GameController framework is not available on this platform.", isError: true)
    }
    #endif
}

private struct ControllerInfoRow: View {
    let controller: GameControllerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(controller.name, systemImage: "gamecontroller.fill").font(.headline)
                Spacer()
                if controller.isCurrent { Text("Current").font(.caption.weight(.semibold)).foregroundStyle(.tint) }
            }
            LabeledContent("Category", value: controller.category)
            LabeledContent("Profile", value: controller.profile)
            LabeledContent("Battery", value: controller.battery)
            LabeledContent("Haptics", value: controller.haptics)
        }
        .padding(.vertical, 4)
    }
}

private struct ControllerInputView: View {
    let input: ControllerInputState

    private var chipWidth: CGFloat {
        #if os(tvOS)
        220
        #else
        110
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live input · \(input.controllerName) · \(input.profile)", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                ForEach(input.sticks) { ControllerStickView(stick: $0) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipWidth), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(input.buttons) { ControllerButtonChip(button: $0) }
            }
            Text(input.lastChange.map { "Last change: \($0)" } ?? "Press a button or move a stick.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ControllerStickView: View {
    let stick: ControllerStickState

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                Circle().fill(.tint).frame(width: 12, height: 12)
                    .offset(x: CGFloat(stick.x) * 26, y: CGFloat(-stick.y) * 26)
            }
            .frame(width: 64, height: 64)
            Text(stick.name).font(.caption).lineLimit(1)
            Text("\(Self.format(stick.x)) · \(Self.format(stick.y))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    static func format(_ value: Float) -> String { Double(value).formatted(.number.precision(.fractionLength(2))) }
}

private struct ControllerButtonChip: View {
    let button: ControllerButtonState

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = button.symbol { Image(systemName: symbol) }
            Text(button.name).lineLimit(1)
            if button.isAnalog { Text(Double(button.value).formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(button.isPressed ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.quaternary), in: Capsule())
    }
}
