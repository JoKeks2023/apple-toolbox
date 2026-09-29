import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// A measurement run of the Live Activities experiment. Compiled into the iOS app, which starts, updates and ends it,
/// and into the widget extension, which draws it on the Lock Screen and in the Dynamic Island.
/// ActivityKit encodes it outside the main actor, so it is nonisolated.
nonisolated struct ToolboxActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            case measuring, finished

            var title: String { self == .measuring ? "Measuring" : "Finished" }
        }

        var phase: Phase
        var sample: Int
        var totalSamples: Int
        /// Short real reading of this sample, e.g. "Battery 82 %".
        var reading: String
        /// Second line with the remaining values of the sample.
        var detail: String
        var updatedAt: Date

        var progress: Double {
            totalSamples > 0 ? min(max(Double(sample) / Double(totalSamples), 0), 1) : 0
        }
    }

    var runName: String
    var symbolName: String
    var startedAt: Date
    var plannedEnd: Date
}
#endif
