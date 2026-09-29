import Foundation

extension ExperimentRegistry {
    static let home: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "homekit-discovery", name: "HomeKit Discovery", category: .home,
            description: "Discover homes, rooms, and accessories through the public HomeKit home manager.", frameworks: ["HomeKit"], supportedPlatforms: [.iOS, .iPadOS, .watchOS, .tvOS], hardwareRequirements: ["HomeKit home or simulator"], osRequirements: ["iOS 8+ · watchOS 2+ · tvOS 10+"], permissions: ["HomeKit access"], capabilities: ["HomeKit"], entitlements: ["HomeKit"], documentationURL: URL(string: "https://developer.apple.com/documentation/homekit")!, evaluate: ExperimentAvailability.homeKit),
        ExperimentDescriptor(id: "matter-status", name: "Matter Accessory Setup", category: .home,
            description: "Start Apple Home's accessory setup flow to commission a Matter accessory into a home, then inspect the returned home and accessory identifiers or the real error.", frameworks: ["HomeKit"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["Matter accessory with its setup code"], osRequirements: ["iOS 15.4+ · iPadOS 15.4+"], permissions: [], capabilities: ["HomeKit", "Matter"], entitlements: ["com.apple.developer.homekit"], documentationURL: URL(string: "https://developer.apple.com/documentation/homekit/hmaccessorysetupmanager")!, evaluate: ExperimentAvailability.matterSetup,
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Apple Toolbox starts Apple Home's accessory setup only on iPhone and iPad; watchOS and tvOS have no setup API.", required: "iOS or iPadOS 15.4+ with Apple Home",
                    nextStep: "Open Apple Toolbox on an iPhone or iPad."),
                .unavailable: ExperimentExplanation(reason: "The system reports that accessory setup is not supported on this device (HMAccessorySetupManager.isSupported is false).", required: "An iPhone or iPad that supports Apple Home accessory setup",
                    nextStep: "Run the experiment on a physical iPhone or iPad with Apple Home set up."),
            ]),
    ]
}
