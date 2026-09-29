import Foundation
import Combine
import HealthKit
import WatchKit
import WidgetKit

nonisolated struct HeartRateReading: Equatable, Sendable {
    let beatsPerMinute: Double
    let date: Date
    let source: String
    let context: String

    init(_ sample: HKQuantitySample) {
        beatsPerMinute = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        date = sample.endDate
        source = sample.sourceRevision.source.name
        context = switch (sample.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue {
        case HKHeartRateMotionContext.sedentary.rawValue: "At rest"
        case HKHeartRateMotionContext.active.rawValue: "Active"
        default: "No motion context"
        }
    }
}

/// Reads heart rate on the watch with an HKAnchoredObjectQuery: the last day's samples first, then every new one.
@MainActor
final class WatchHeartRateService: ObservableObject {
    @Published private(set) var latest: HeartRateReading?
    @Published private(set) var received = 0
    @Published private(set) var isRunning = false
    @Published private(set) var output = "Start to request read access to heart rate and follow new samples."
    private let store = HKHealthStore()
    private let heartRate = HKQuantityType(.heartRate)
    private var query: HKAnchoredObjectQuery?

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func start() {
        guard !isRunning else { return }
        guard isHealthDataAvailable else {
            output = "HKHealthStore.isHealthDataAvailable() is false on this device."
            return
        }
        isRunning = true
        output = "Requesting read access to heart rate…"
        Task {
            do {
                try await store.requestAuthorization(toShare: [], read: [heartRate])
            } catch {
                isRunning = false
                output = "Authorization failed: \(error.localizedDescription)\nThe watch app needs the HealthKit entitlement and NSHealthShareUsageDescription."
                return
            }
            guard isRunning else { return }
            runQuery()
        }
    }

    func stop() {
        if let query { store.stop(query) }
        query = nil
        isRunning = false
        output = "Stopped. \(received) sample(s) received."
    }

    private func runQuery() {
        let since = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-24 * 3600), end: nil)
        // HealthKit calls both handlers on a background queue, so they only hand Sendable readings to the main actor.
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, (any Error)?) -> Void = { [weak self] _, samples, _, _, error in
            let readings = (samples ?? []).compactMap { $0 as? HKQuantitySample }.map(HeartRateReading.init)
            let failure = error?.localizedDescription
            Task { @MainActor in self?.receive(readings, failure: failure) }
        }
        let query = HKAnchoredObjectQuery(type: heartRate, predicate: since, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        self.query = query
        output = "Query running. Apple Watch records heart rate every few minutes (continuously only during workouts)."
    }

    private func receive(_ readings: [HeartRateReading], failure: String?) {
        guard isRunning else { return }
        if let failure {
            // Denied read access looks like an empty result; errors come from missing entitlements or a locked device.
            output = "HealthKit returned an error: \(failure)"
            return
        }
        received += readings.count
        guard let newest = readings.max(by: { $0.date < $1.date }), newest.date > (latest?.date ?? .distantPast) else {
            if latest == nil {
                output = "No heart rate samples in the last 24 hours. If access was denied, HealthKit reports no samples instead of an error; check Settings › Health › Data Access."
            }
            return
        }
        latest = newest
        output = "\(received) sample(s) received. Waiting for new samples…"
        WatchComplicationStore.update {
            $0.heartRate = newest.beatsPerMinute
            $0.heartRateDate = newest.date
            $0.source = "Heart rate"
            $0.updatedAt = .now
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationStore.widgetKind)
    }
}

/// Keeps the complication current: writes the snapshot, reloads the widget timeline and schedules background refresh.
@MainActor
enum WatchComplicationUpdater {
    /// How far ahead the next background refresh is requested; watchOS budgets the actual runs.
    static let refreshInterval: TimeInterval = 30 * 60

    static func record(source: String) {
        let statuses = ExperimentRegistry.all.map(\.currentStatus)
        WatchComplicationStore.update {
            $0.availableCount = statuses.filter { $0 == .available }.count
            $0.totalCount = statuses.count
            $0.source = source
            $0.updatedAt = .now
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationStore.widgetKind)
    }

    static func recordPing(_ message: String) {
        WatchComplicationStore.update {
            $0.lastPing = message
            $0.lastPingDate = .now
            $0.source = "iPhone link"
            $0.updatedAt = .now
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationStore.widgetKind)
    }

    /// Runs from `.backgroundTask(.appRefresh(_:))`: refresh the data, then ask for the next run.
    static func handleBackgroundRefresh() async {
        record(source: "Background refresh")
        _ = await scheduleNextRefresh()
    }

    /// Only one background refresh can be pending; scheduling again replaces it.
    @discardableResult
    static func scheduleNextRefresh() async -> String {
        let date = Date().addingTimeInterval(refreshInterval)
        // The completion may run on any queue, so it only passes the error text back.
        let failure: String? = await withCheckedContinuation { continuation in
            WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: WatchComplicationStore.refreshIdentifier as NSString) { @Sendable error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
        if let failure { return "scheduleBackgroundRefresh failed: \(failure)" }
        WatchComplicationStore.update { $0.nextRefresh = date }
        return "Background refresh requested for \(date.formatted(date: .omitted, time: .shortened)). watchOS decides when it actually runs."
    }
}
