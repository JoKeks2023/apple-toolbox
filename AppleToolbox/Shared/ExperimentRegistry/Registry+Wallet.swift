import Foundation

extension ExperimentRegistry {
    static let wallet: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "wallet-status", name: "Wallet & PassKit", category: .wallet,
            description: "Inspect PassKit availability and the passes visible to this app.", frameworks: ["PassKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["Current OS with PassKit support"], permissions: [], capabilities: ["Wallet"], entitlements: ["Wallet for advanced credentials"], documentationURL: URL(string: "https://developer.apple.com/documentation/passkit")!, evaluate: ExperimentAvailability.wallet),
        ExperimentDescriptor(id: "wallet-creator", name: "Wallet Pass Creator", category: .wallet,
            description: "Create and export a real pass.json draft. An installable Apple Wallet pass still requires Apple signing credentials.", frameworks: ["PassKit", "Foundation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 6+ · macOS 10.9+"], permissions: ["User-selected export destination"], capabilities: ["Wallet pass format"], entitlements: ["Pass Type ID certificate for installable .pkpass"], documentationURL: URL(string: "https://developer.apple.com/documentation/walletpasses")!, evaluate: { [.iOS, .iPadOS, .macOS].contains(CurrentPlatform.value) ? .approvalRequired : .platformUnsupported },
            applePrograms: ["Apple Developer Program: signing an installable pass needs a Pass Type ID certificate"]),
    ]
}
