import Foundation

extension ExperimentRegistry {
    static let developer: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "capability-explorer", name: "Capability Explorer", category: .developer,
            description: "Scan this device with public APIs: hardware, sensors, cameras, display, and Apple features, each reported as available, unavailable, or unknown without triggering a permission prompt.", frameworks: ["Device capability APIs", "CoreMotion", "CoreLocation", "AVFoundation", "LocalAuthentication", "NearbyInteraction", "FoundationModels"], supportedPlatforms: SupportedPlatform.allCases, hardwareRequirements: [], osRequirements: ["Current Apple OS"], permissions: [], capabilities: ["Device and framework inspection"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/entitlements")!, evaluate: { .available }),
        ExperimentDescriptor(id: "developer-tools", name: "Developer Tools Lab", category: .developer,
            description: "Catalog of Apple's developer tools and diagnostic utilities, what each does, and which parts the Toolbox reproduces with public APIs.",
            frameworks: ["Xcode", "Developer tools"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: [], osRequirements: ["Any supported OS"], permissions: [], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/xcode/")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "tools-map", title: "Find the right tool", summary: "See which Apple tool answers a question and where the Toolbox covers the same ground on the device.", interaction: "Filter by tool type, expand a tool, and jump to the related experiment.")),
        ExperimentDescriptor(id: "diagnostics", name: "Diagnostics", category: .developer,
            description: "Read this app's own unified log, measure a workload with signposts, receive MetricKit payloads, and inspect thermal, memory, MDM configuration and cellular radio state.",
            frameworks: ["OSLog", "MetricKit", "os.signpost", "CoreTelephony"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 15+ · macOS 12+ · tvOS 15+"], permissions: [], capabilities: [], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/oslog/oslogstore")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "diagnostics-console", title: "Diagnose the app like Console and Instruments", summary: "Use the public diagnostics APIs behind Console, Instruments and the Organizer from inside the app.", interaction: "Write a log entry, load the app's log, measure a signposted workload, and subscribe to MetricKit.")),
    ]
}
