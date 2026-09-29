import Foundation

extension ExperimentRegistry {
    static let health: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "healthkit-status", name: "HealthKit Reader", category: .health,
            description: "Request read access for a chosen set of Health data types, then read recent activity, heart, sleep, workout, respiratory, mobility and environmental samples and daily step totals; run an observer query with background delivery and see the Health Records boundary.",
            frameworks: ["HealthKit"], supportedPlatforms: [.iOS, .iPadOS, .watchOS],
            hardwareRequirements: ["iPhone or Apple Watch with Health data (iPad on iPadOS 17+)"],
            osRequirements: ["iOS 8+ · watchOS 2+", "Sleep stages and workout statistics: iOS 16+ · watchOS 9+", "Background delivery: watchOS 8+; entitlement required since iOS 15"],
            permissions: ["HealthKit read authorization per data type (HealthKit never reveals what was allowed)"],
            capabilities: ["HealthKit", "HealthKit Background Delivery"], entitlements: ["com.apple.developer.healthkit", "com.apple.developer.healthkit.background-delivery"],
            documentationURL: URL(string: "https://developer.apple.com/documentation/healthkit")!, evaluate: ExperimentAvailability.healthKit,
            useCase: ExperimentUseCase(id: "health-reader", title: "Read your own Health data", summary: "See what an app can read from HealthKit: recent samples per type, daily step sums, workouts with duration and energy, last night's sleep stages, and live updates from an observer query.", interaction: "Pick a data set, request read access, then read recent samples. Start the observer and add data in the Health app to watch HealthKit report it."),
            explanations: [
                .permissionRequired: ExperimentExplanation(reason: "Apple Toolbox has not asked for Health read access on this device yet. HealthKit never tells apps whether reading was allowed, so afterwards this only records that the request was made.", required: "HealthKit read authorization for the chosen data set",
                    nextStep: "Pick a data set and tap Request Read Access; the Health sheet lists every type."),
                .hardwareUnsupported: ExperimentExplanation(reason: "Health data is not available on this device.", required: "iPhone, Apple Watch or an iPad with the Health app",
                    nextStep: "Run the experiment on iPhone or Apple Watch."),
            ]),
    ]
}
