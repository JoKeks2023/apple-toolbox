import Foundation

extension ExperimentRegistry {
    static let health: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "healthkit-status", name: "HealthKit Status", category: .health,
            description: "Check HealthKit availability and explain its authorization and entitlement boundary.", frameworks: ["HealthKit"], supportedPlatforms: [.iOS, .iPadOS, .watchOS], hardwareRequirements: ["Health-capable device"], osRequirements: ["iOS 8+ · watchOS 2+"], permissions: ["HealthKit authorization"], capabilities: ["HealthKit"], entitlements: ["HealthKit"], documentationURL: URL(string: "https://developer.apple.com/documentation/healthkit")!, evaluate: ExperimentAvailability.healthKit,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "Health data is not available on this device.", required: "iPhone, Apple Watch or an iPad with the Health app",
                    nextStep: "Run the experiment on iPhone or Apple Watch."),
            ]),
    ]
}
