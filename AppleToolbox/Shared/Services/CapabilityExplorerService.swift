import Foundation

enum CapabilityExplorerService {
    /// Plain-text rendering of a scan, for selecting and copying the whole report.
    static func report(_ scan: DeviceScanReport) -> String {
        var lines = [
            "Device capability scan · \(scan.platform) · \(scan.date.formatted(date: .abbreviated, time: .standard))",
            "\(scan.count(.available)) available · \(scan.count(.unavailable)) unavailable · \(scan.count(.unknown)) unknown"
        ]
        for section in scan.sections {
            lines.append("")
            lines.append(section.title.uppercased())
            lines += section.items.map { "\($0.state.marker) \($0.name): \($0.detail)" }
        }
        lines.append("")
        lines.append("Only public APIs are queried and no permission is requested. Entitlements are not inferred from API presence; each experiment lists its exact capability or entitlement boundary.")
        return lines.joined(separator: "\n")
    }
}
