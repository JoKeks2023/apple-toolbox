import SwiftUI

struct DeviceScannerRunView: View {
    @State private var report: DeviceScanReport?
    @State private var isScanning = false
    @State private var showsText = false

    var body: some View {
        Button(isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise") { Task { await scan() } }
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
            .task { if report == nil { await scan() } }
        if let report {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scanned \(report.date.formatted(date: .omitted, time: .standard)) · \(report.platform)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    InfoChip(title: "\(report.count(.available)) available", symbol: "checkmark.circle")
                    InfoChip(title: "\(report.count(.unavailable)) unavailable", symbol: "xmark.circle")
                    InfoChip(title: "\(report.count(.unknown)) unknown", symbol: "questionmark.circle")
                }
            }
            ForEach(report.sections) { CapabilitySectionView(section: $0) }
            Toggle("Show plain-text report", isOn: $showsText)
            if showsText { OutputView(text: CapabilityExplorerService.report(report), isError: false) }
        } else {
            ProgressView("Scanning device capabilities…")
        }
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        report = await DeviceScanner.scan()
        isScanning = false
    }
}

private struct CapabilitySectionView: View {
    let section: CapabilitySection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(section.title, systemImage: section.symbol)
                .font(.headline)
            ForEach(section.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline.weight(.medium))
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    CapabilityStateBadge(state: item.state)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
        .tvFocusableRow()
    }
}

private struct CapabilityStateBadge: View {
    let state: CapabilityState

    var body: some View {
        Label(state.rawValue, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var symbol: String {
        switch state {
        case .available: "checkmark.circle.fill"
        case .unavailable: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .available: .green
        case .unavailable: .orange
        case .unknown: .gray
        }
    }
}
