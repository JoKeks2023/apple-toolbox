import Foundation

nonisolated extension ImplementationGuides {
    static let health: [String: ImplementationGuide] = [
        "healthkit-status": ImplementationGuide(
            snippet: #"""
            import HealthKit

            /// Reads today's step count with the async query descriptors.
            final class StepCounter: Sendable {
                private let store = HKHealthStore()

                func todaysSteps() async throws -> Double {
                    guard HKHealthStore.isHealthDataAvailable() else { return 0 }
                    let steps = HKQuantityType(.stepCount)
                    try await store.requestAuthorization(toShare: [], read: [steps])

                    let today = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: nil)
                    let query = HKStatisticsQueryDescriptor(
                        predicate: .quantitySample(type: steps, predicate: today),
                        options: .cumulativeSum)
                    let statistics = try await query.result(for: store)
                    return statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSHealthShareUsageDescription", value: "Shows your daily step count."),
                .init(key: "NSHealthUpdateUsageDescription", value: "Saves workouts you record in the app."),
            ],
            entitlements: [
                "com.apple.developer.healthkit = true",
                "com.apple.developer.healthkit.background-delivery = true (only with enableBackgroundDelivery)",
            ],
            capabilities: ["HealthKit"],
            notes: [
                "Read permission is private: a denied type simply returns no samples, so never treat an empty result as 'denied'.",
                "HealthKit is not available on iPad before iPadOS 17; always check isHealthDataAvailable().",
                "App Review requires a clear health purpose, and health data must not be used for advertising (guideline 5.1.3).",
            ]
        ),
    ]
}
