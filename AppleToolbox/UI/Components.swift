import SwiftUI

enum ExperimentOutput {
    /// First text shown in an experiment's output card before anything ran.
    static func initialMessage(for status: ExperimentStatus) -> String {
        switch status {
        case .hardwareUnsupported: "Why this doesn't work: required hardware is not available on this device or simulator."
        case .platformUnsupported: "Why this doesn't work: this experiment is not supported on the current platform."
        case .permissionRequired: "Permission has not been evaluated yet. Use the permission action above."
        default: "Ready. Results from the real system API will appear here."
        }
    }
}

struct OutputView: View {
    let text: String
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(isError ? "Live error" : "Live output", systemImage: isError ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isError ? .red : .secondary)
            #if os(tvOS)
            Text(text).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
            #else
            Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        .padding(14)
        .background((isError ? Color.red : Color.secondary).opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke((isError ? Color.red : Color.secondary).opacity(0.18), lineWidth: 1)
        }
    }
}

struct StatusBadge: View {
    let status: ExperimentStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .available ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

struct InfoChip: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}

/// A single button that queries an API and prints the returned report.
struct StatusCheckRunView: View {
    let title: String
    let check: () -> String
    @State private var output: String

    init(experiment: ExperimentDescriptor, title: String, check: @escaping () -> String) {
        self.title = title
        self.check = check
        _output = State(initialValue: ExperimentOutput.initialMessage(for: experiment.currentStatus))
    }

    var body: some View {
        Button(title) { output = check() }.buttonStyle(.borderedProminent)
        OutputView(text: output, isError: false)
    }
}
