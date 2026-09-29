import SwiftUI

enum ExperimentOutput {
    /// First text shown in an experiment's output card before anything ran.
    static func initialMessage(for status: ExperimentStatus) -> String {
        switch status {
        case .available: "Ready. Results from the real system API will appear here."
        case .permissionRequired: "Permission has not been granted yet. The system asks when the experiment starts."
        default: "Not available right now. See “Why doesn't this work?” above; results from the real system API will still appear here."
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
        .tvFocusableRow()
    }
}

extension View {
    /// On tvOS the Siri Remote only moves focus, and a list scrolls only to focusable views, so read-only rows
    /// (output, facts, checks) are made focusable there to stay reachable. Does nothing on other platforms.
    func tvFocusableRow() -> some View {
        #if os(tvOS)
        modifier(TVFocusableRow())
        #else
        self
        #endif
    }

    /// Makes every `LabeledContent` row below this view focusable on tvOS (see `tvFocusableRow()`), so run views
    /// don't need to mark each fact row. Only use it where labeled content holds text, not controls.
    func tvFocusableLabeledContent() -> some View {
        #if os(tvOS)
        labeledContentStyle(TVFocusableLabeledContentStyle())
        #else
        self
        #endif
    }
}

#if os(tvOS)
private struct TVFocusableRow: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(isFocused ? 0.12 : 0))
                    .padding(-8)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// Keeps the list's own labeled-content layout and only adds focusability.
private struct TVFocusableLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent(configuration).tvFocusableRow()
    }
}
#endif

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
