import Foundation

extension ExperimentRegistry {
    static let home: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "homekit-discovery", name: "Home Inspector", category: .home,
            description: "Browse homes, rooms, accessories, services and characteristics with their types, properties, units and ranges; read and write values, follow live changes, run scenes, and list automations with their events and conditions.",
            frameworks: ["HomeKit"], supportedPlatforms: [.iOS, .iPadOS, .watchOS, .tvOS],
            hardwareRequirements: ["A home with accessories (real or from the HomeKit Accessory Simulator)", "Home hub (Apple TV or HomePod) for automations"],
            osRequirements: ["iOS 8+ · watchOS 2+ · tvOS 10+", "Manufacturer, model and firmware: iOS 11+ · watchOS 4+ · tvOS 11+", "Matter node IDs: iOS 16.1+ · watchOS 9.1+ · tvOS 16.1+"],
            permissions: ["HomeKit access (asked when the homes are loaded)"], capabilities: ["HomeKit"], entitlements: ["com.apple.developer.homekit"],
            documentationURL: URL(string: "https://developer.apple.com/documentation/homekit")!, evaluate: ExperimentAvailability.homeKit,
            useCase: ExperimentUseCase(id: "home-inspector", title: "Home Inspector", summary: "Inspect every accessory the way HomeKit sees it: services, characteristic types, formats, units, ranges and live values, plus the home's scenes and automations.", interaction: "Load the homes, pick a room and an accessory, read or write a characteristic and turn on Notify to watch changes arrive. Without real accessories, pair ones from the HomeKit Accessory Simulator."),
            explanations: [
                .permissionDenied: ExperimentExplanation(reason: "HomeKit access was denied or is restricted, so HMHomeManager returns no homes.", required: "HomeKit access for Apple Toolbox",
                    nextStep: "Allow it in Settings › Privacy & Security › HomeKit, then load the homes again."),
                .platformUnsupported: ExperimentExplanation(reason: "HomeKit's home data API is available on iPhone, iPad, Apple TV and Apple Watch; native macOS apps cannot use it (only Mac Catalyst apps).", required: "iOS, iPadOS, tvOS or watchOS",
                    nextStep: "Open Apple Toolbox on an iPhone, iPad or Apple TV."),
            ]),
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
