import Foundation
import Combine
import OSLog
import CryptoKit
#if canImport(MetricKit) && (os(iOS) || os(macOS))
import MetricKit
#endif
#if canImport(CoreTelephony) && os(iOS)
import CoreTelephony
#endif

nonisolated struct DiagnosticLogLine: Identifiable, Sendable {
    let id: Int
    let date: Date
    let level: String
    let category: String
    let message: String
}

enum DiagnosticLogLevel: String, CaseIterable, Identifiable {
    case debug = "Debug", info = "Info", notice = "Notice", error = "Error", fault = "Fault"
    var id: String { rawValue }
}

/// Diagnostic-inspired utilities with public APIs (spec §33–34): the app's own unified log (Console),
/// signposts (Instruments), MetricKit payloads (Organizer), managed app configuration (MDM) and the
/// cellular radio access technology (Field Test Mode's public subset).
@MainActor
final class DiagnosticsExperimentService: NSObject, ObservableObject {
    nonisolated static let subsystem = Bundle.main.bundleIdentifier ?? ToolboxIdentifiers.base
    private static let logger = Logger(subsystem: subsystem, category: "Diagnostics")

    @Published private(set) var output = "Write test entries or load the app's own log."
    @Published private(set) var logLines: [DiagnosticLogLine] = []
    @Published private(set) var isLoadingLogs = false
    @Published private(set) var signpostResult: String?
    @Published private(set) var metricKitState = "Not subscribed"
    @Published private(set) var metricPayloads: [String] = []

    var systemRows: [(String, String)] {
        let info = ProcessInfo.processInfo
        let thermal: String = switch info.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
        return [
            ("OS", info.operatingSystemVersionString),
            ("Thermal state", thermal),
            ("Low Power Mode", info.isLowPowerModeEnabled ? "On" : "Off"),
            ("Physical memory", ByteCountFormatter.string(fromByteCount: Int64(info.physicalMemory), countStyle: .memory)),
            ("Active processors", "\(info.activeProcessorCount) of \(info.processorCount)"),
            ("Managed app configuration", Self.managedConfigurationSummary),
            ("Cellular radio", Self.radioAccessTechnology),
        ]
    }

    func writeTestEntries(level: DiagnosticLogLevel) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        switch level {
        case .debug: Self.logger.debug("Apple Toolbox debug entry at \(stamp, privacy: .public)")
        case .info: Self.logger.info("Apple Toolbox info entry at \(stamp, privacy: .public)")
        case .notice: Self.logger.notice("Apple Toolbox notice entry at \(stamp, privacy: .public)")
        case .error: Self.logger.error("Apple Toolbox error entry at \(stamp, privacy: .public)")
        case .fault: Self.logger.fault("Apple Toolbox fault entry at \(stamp, privacy: .public)")
        }
        output = "Wrote a \(level.rawValue.lowercased()) entry to the unified log (subsystem \(Self.subsystem)). Debug and info entries are only kept in memory and may not be persisted."
    }

    func loadLogs(minutes: Int) async {
        isLoadingLogs = true
        output = "Reading the unified log…"
        let result = await Self.readOwnLog(since: Date().addingTimeInterval(-Double(minutes) * 60))
        isLoadingLogs = false
        switch result {
        case .success(let lines):
            logLines = lines
            output = lines.isEmpty ? "No entries from this app in the last \(minutes) minutes." : "Read \(lines.count) entries from this process via OSLogStore."
        case .failure(let error):
            logLines = []
            output = "OSLogStore error: \(error.localizedDescription)"
        }
    }

    /// OSLogStore reads can take a while, so they run off the main actor.
    @concurrent nonisolated private static func readOwnLog(since date: Date) async -> Result<[DiagnosticLogLine], Error> {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(at: store.position(date: date), matching: NSPredicate(format: "subsystem == %@", subsystem))
            var lines: [DiagnosticLogLine] = []
            for (index, entry) in entries.enumerated() {
                guard let log = entry as? OSLogEntryLog else { continue }
                lines.append(DiagnosticLogLine(id: index, date: log.date, level: levelName(log.level), category: log.category, message: log.composedMessage))
            }
            return .success(Array(lines.suffix(100).reversed()))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .error: "Error"
        case .fault: "Fault"
        case .undefined: "Undefined"
        @unknown default: "Unknown"
        }
    }

    /// Measures a CPU workload inside an os_signpost interval that Instruments shows in Points of Interest.
    func measureSignpost() {
        let signposter = OSSignposter(subsystem: Self.subsystem, category: .pointsOfInterest)
        let data = Data(repeating: 0x5A, count: 1_000_000)
        let clock = ContinuousClock()
        let state = signposter.beginInterval("SHA-256 workload")
        let elapsed = clock.measure {
            for _ in 0..<50 { _ = SHA256.hash(data: data) }
        }
        signposter.endInterval("SHA-256 workload", state)
        signpostResult = "Hashed 50 MB in \(elapsed.formatted(.units(allowed: [.milliseconds], width: .abbreviated))) inside a \"SHA-256 workload\" signpost interval."
    }

    private static var managedConfigurationSummary: String {
        // MDM-delivered managed app configuration (Apple Business Manager / any MDM).
        guard let configuration = UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed") else { return "None (not delivered by an MDM)" }
        return "\(configuration.count) key(s): \(configuration.keys.sorted().joined(separator: ", "))"
    }

    private static var radioAccessTechnology: String {
        #if canImport(CoreTelephony) && os(iOS) && !targetEnvironment(simulator)
        let technologies = CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology ?? [:]
        guard !technologies.isEmpty else { return "No active cellular service" }
        return technologies.values.map { $0.replacingOccurrences(of: "CTRadioAccessTechnology", with: "") }.sorted().joined(separator: ", ")
        #else
        return "Not available on this platform or in the Simulator"
        #endif
    }

    // MARK: MetricKit

    func subscribeToMetrics() {
        #if canImport(MetricKit) && (os(iOS) || os(macOS))
        let manager = MXMetricManager.shared
        manager.add(self)
        metricKitState = "Subscribed. MetricKit delivers payloads at most once a day."
        let past = manager.pastPayloads.map(Self.summary) + manager.pastDiagnosticPayloads.map(Self.summary)
        metricPayloads = past
        output = past.isEmpty ? "No MetricKit payloads have been delivered to this app yet." : "Loaded \(past.count) past MetricKit payload(s)."
        #else
        metricKitState = "MetricKit is not available on this platform."
        #endif
    }

    #if canImport(MetricKit) && (os(iOS) || os(macOS))
    nonisolated private static func summary(_ payload: MXMetricPayload) -> String {
        let interval = "\(payload.timeStampBegin.formatted(date: .abbreviated, time: .shortened)) – \(payload.timeStampEnd.formatted(date: .omitted, time: .shortened))"
        return "Metrics \(interval) · \(payload.jsonRepresentation().count) bytes JSON"
    }

    nonisolated private static func summary(_ payload: MXDiagnosticPayload) -> String {
        let counts = [("crashes", payload.crashDiagnostics?.count ?? 0), ("hangs", payload.hangDiagnostics?.count ?? 0),
                      ("CPU exceptions", payload.cpuExceptionDiagnostics?.count ?? 0), ("disk writes", payload.diskWriteExceptionDiagnostics?.count ?? 0)]
        return "Diagnostics \(payload.timeStampEnd.formatted(date: .abbreviated, time: .shortened)) · " + counts.map { "\($0.1) \($0.0)" }.joined(separator: ", ")
    }
    #endif
}

#if canImport(MetricKit) && (os(iOS) || os(macOS))
extension DiagnosticsExperimentService: MXMetricManagerSubscriber {
    // MetricKit calls the subscriber on a background queue.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let summaries = payloads.map(Self.summary)
        Task { @MainActor [weak self] in self?.metricPayloads.insert(contentsOf: summaries, at: 0) }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let summaries = payloads.map(Self.summary)
        Task { @MainActor [weak self] in self?.metricPayloads.insert(contentsOf: summaries, at: 0) }
    }
}
#endif
