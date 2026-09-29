import Foundation

extension ExperimentRegistry {
    static let developer: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "capability-explorer", name: "Capability Explorer", category: .developer,
            description: "Scan this device with public APIs: hardware, sensors, cameras, display, and Apple features, each reported as available, unavailable, or unknown without triggering a permission prompt.", frameworks: ["Device capability APIs", "CoreMotion", "CoreLocation", "AVFoundation", "LocalAuthentication", "NearbyInteraction", "FoundationModels"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["Current Apple OS"], permissions: [], capabilities: ["Device and framework inspection"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/entitlements")!, evaluate: { .available }),
    ]
}
