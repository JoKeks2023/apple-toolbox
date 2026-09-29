import Foundation

extension ExperimentRegistry {
    static let location: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "core-location", name: "Core Location", category: .location,
            description: "Inspect live coordinates, precise vs. approximate accuracy, heading and floor, and monitor a region, visits, and significant changes around you.",
            frameworks: ["CoreLocation"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: ["Location hardware or a simulated location", "Magnetometer for heading"], osRequirements: ["iOS 6+ · macOS 10.9+ · watchOS 2+", "CLMonitor: iOS 17+ · macOS 14+"], permissions: ["Location When In Use", "Temporary precise location (purpose key)", "Location Always (optional upgrade for visits and significant changes)"], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/corelocation")!, evaluate: ExperimentAvailability.location,
            useCase: ExperimentUseCase(id: "location-dashboard", title: "Build a live location dashboard", summary: "Use the device's real location stream, heading, and a geofence around you.", interaction: "Grant permission and start updates, then monitor a region around you and walk in or out to see entry and exit events. Upgrade to Always only if you want visits and significant changes."),
            explanations: [
                .permissionRequired: ExperimentExplanation(reason: "The app has not asked for location access yet.", required: "Location When In Use (Always only for visits and significant changes)",
                    nextStep: "Tap Request Location Permission; the Always upgrade is offered separately."),
                .permissionDenied: ExperimentExplanation(reason: "Location access is denied, restricted by Screen Time or MDM, or Location Services are off.", required: "Location Services on and Apple Toolbox allowed While Using the App",
                    nextStep: "Turn on Settings › Privacy & Security › Location Services and allow Apple Toolbox."),
            ]),
    ]
}
