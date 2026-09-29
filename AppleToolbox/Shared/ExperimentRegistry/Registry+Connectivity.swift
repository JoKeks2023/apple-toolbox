import Foundation

extension ExperimentRegistry {
    static let connectivity: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "core-bluetooth", name: "Core Bluetooth", category: .connectivity,
            description: "Scan for nearby Bluetooth Low Energy peripherals, connect to one, and explore its GATT database: services, characteristics and descriptors, reads, writes, notifications, RSSI and maximum write length.", frameworks: ["CoreBluetooth"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .watchOS], hardwareRequirements: ["Bluetooth hardware"], osRequirements: ["iOS 5+ · macOS 10.9+ · watchOS 4+"], permissions: ["Bluetooth Usage Description"], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/corebluetooth")!, evaluate: ExperimentAvailability.bluetooth,
            useCase: ExperimentUseCase(id: "gatt-explorer", title: "Explore a peripheral's GATT database", summary: "Connect to a heart-rate strap, a sensor, a smart bulb, or a second device running Bluetooth Peripheral Mode and inspect everything it exposes.", interaction: "Start a scan, tap Connect on a peripheral, expand a service, then read, write or subscribe to a characteristic and watch the live log."),
            explanations: [
                .permissionDenied: ExperimentExplanation(reason: "Bluetooth access is denied or restricted for Apple Toolbox.", required: "Bluetooth permission (NSBluetoothAlwaysUsageDescription)",
                    nextStep: "Allow Bluetooth for Apple Toolbox in Settings › Privacy & Security › Bluetooth."),
            ]),
        ExperimentDescriptor(id: "multipeer-connectivity", name: "MultipeerConnectivity", category: .connectivity,
            description: "Discover nearby Apple Toolbox devices, connect them automatically, and exchange live messages over a local peer-to-peer session.", frameworks: ["MultipeerConnectivity"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Wi-Fi or Bluetooth for nearby peer discovery"], osRequirements: ["iOS 7+ · macOS 10.10+"], permissions: ["Local Network Usage Description"], capabilities: ["Local peer-to-peer networking"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/multipeerconnectivity")!, evaluate: { [.iOS, .iPadOS, .macOS].contains(CurrentPlatform.value) ? .available : .platformUnsupported },
            useCase: ExperimentUseCase( id: "multipeer-messaging", title: "Nearby device messaging", summary: "Turn two Apple devices into a small local playground without a server or internet connection.", interaction: "Start discovery on both devices, accept the connection, then send a message between them." )),
        ExperimentDescriptor(id: "continuity", name: "WatchConnectivity", category: .connectivity,
            description: "Activate the public WatchConnectivity session and inspect reachability.", frameworks: ["WatchConnectivity"], supportedPlatforms: [.iOS, .watchOS], hardwareRequirements: ["Apple Watch pairing for reachability"], osRequirements: ["iOS 9+ · watchOS 2+"], permissions: [], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/watchconnectivity")!, evaluate: ExperimentAvailability.watchConnectivity,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "WatchConnectivity is only supported on iPhone.", required: "An iPhone paired with an Apple Watch",
                    nextStep: "Run the experiment on the iPhone that is paired with your watch."),
            ]),
        ExperimentDescriptor(id: "nearby-interaction", name: "Nearby Interaction / UWB", category: .connectivity,
            description: "Inspect Nearby Interaction device capabilities and prepare a real peer-ranging session using discovery tokens.", frameworks: ["NearbyInteraction"], supportedPlatforms: [.iOS, .iPadOS, .watchOS], hardwareRequirements: ["UWB-capable peer devices for precise ranging"], osRequirements: ["iOS 16+ · iPadOS 16+ · watchOS 9+"], permissions: [], capabilities: ["Nearby Interaction", "Ultra Wideband"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/nearbyinteraction")!, evaluate: ExperimentAvailability.nearbyInteraction,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "This device does not provide an Ultra Wideband chip.", required: "iPhone 11 or later, or Apple Watch Series 6 or later",
                    nextStep: "Use two UWB-capable devices running Apple Toolbox."),
            ]),
    ]
}
