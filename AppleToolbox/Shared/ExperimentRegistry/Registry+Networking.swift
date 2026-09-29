import Foundation

extension ExperimentRegistry {
    static let networking: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "network-path", name: "Network Path", category: .networking,
            description: "Monitor live connectivity, available interfaces, cost, and constrained-network state.", frameworks: ["Network"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS, .tvOS], hardwareRequirements: [], osRequirements: ["iOS 12+ · macOS 10.14+ · watchOS 5+ · tvOS 12+"], permissions: [], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/network")!, evaluate: { .available }),
    ]
}
