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
        ExperimentDescriptor(id: "bluetooth-peripheral", name: "Bluetooth Peripheral Mode", category: .connectivity,
            description: "Publish a custom Apple Toolbox GATT service with CBPeripheralManager, advertise it, answer read and write requests, and send notifications to subscribed centrals.", frameworks: ["CoreBluetooth"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Bluetooth LE hardware", "A second device with Apple Toolbox or another BLE central app"], osRequirements: ["iOS 6+ · macOS 10.9+"], permissions: ["Bluetooth Usage Description"], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager")!, evaluate: ExperimentAvailability.bluetooth,
            useCase: ExperimentUseCase(id: "two-device-gatt", title: "Two-device GATT lab", summary: "Turn this device into a Bluetooth LE accessory that a second device can connect to and explore.", interaction: "Start advertising here, open Core Bluetooth on a second device, connect to “Toolbox”, then read Info, write to Inbox and subscribe to Feed."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "CBPeripheralManager is not available on \(CurrentPlatform.value.rawValue); Apple Watch and Apple TV can only act as Bluetooth centrals.", required: "iPhone, iPad or Mac",
                    nextStep: "Advertise from an iPhone, iPad or Mac and explore it from this device with Core Bluetooth."),
                .permissionDenied: ExperimentExplanation(reason: "Bluetooth access is denied or restricted for Apple Toolbox.", required: "Bluetooth permission (NSBluetoothAlwaysUsageDescription)",
                    nextStep: "Allow Bluetooth for Apple Toolbox in Settings › Privacy & Security › Bluetooth."),
            ]),
        ExperimentDescriptor(id: "accessory-setup-kit", name: "AccessorySetupKit", category: .connectivity,
            description: "Activate an ASAccessorySession, list the accessories authorized for Apple Toolbox, and show the system accessory picker for a declared Bluetooth accessory with the real session events and errors.", frameworks: ["AccessorySetupKit", "CoreBluetooth"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["A Bluetooth LE accessory, e.g. a second device in Bluetooth Peripheral Mode"], osRequirements: ["iOS 18+ · iPadOS 18+"], permissions: [], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/accessorysetupkit")!, evaluate: ExperimentAvailability.accessorySetupKit,
            useCase: ExperimentUseCase(id: "accessory-picker", title: "One-tap accessory setup", summary: "See how AccessorySetupKit replaces the broad Bluetooth permission with a per-accessory picker.", interaction: "Activate the session and watch its events; with the Info.plist declaration in place, show the picker while a second device advertises in Bluetooth Peripheral Mode."),
            explanations: [
                .unavailable: ExperimentExplanation(reason: "This build does not declare AccessorySetupKit Bluetooth discovery in Info.plist, and AccessorySetupKit terminates an app whose picker looks for undeclared Bluetooth identifiers.", required: "NSAccessorySetupKitSupports (Bluetooth) plus NSAccessorySetupBluetoothServices and NSAccessorySetupBluetoothNames matching the picker item",
                    nextStep: "Activate the session to see its real events. To try the picker, build with those keys; Apple then limits Core Bluetooth to accessories added through AccessorySetupKit."),
            ]),
        ExperimentDescriptor(id: "external-accessory", name: "External Accessory (MFi)", category: .connectivity,
            description: "List MFi accessories connected over Lightning, USB-C or Bluetooth through EAAccessoryManager and log connect and disconnect notifications.", frameworks: ["ExternalAccessory"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: ["An MFi accessory whose protocol the app declares"], osRequirements: ["iOS 3+ · macOS 10.13+ · tvOS 10+"], permissions: [], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/externalaccessory")!, evaluate: ExperimentAvailability.externalAccessory,
            useCase: ExperimentUseCase(id: "mfi-accessories", title: "See what the MFi layer reports", summary: "Inspect name, manufacturer, model, firmware and protocol strings of connected MFi accessories.", interaction: "Start listening, then connect or disconnect an MFi accessory and watch the notifications arrive."),
            explanations: [
                .unavailable: ExperimentExplanation(reason: "No External Accessory is available to Apple Toolbox right now. The system only reports MFi accessories, and an app talks to one only through protocols it declares.", required: "A connected MFi accessory and its protocol in UISupportedExternalAccessoryProtocols",
                    nextStep: "Connect an MFi accessory and start listening; Bluetooth LE devices appear in Core Bluetooth instead."),
            ],
            applePrograms: ["MFi Program: the accessory maker defines the protocol and authorizes apps that declare it"]),
        ExperimentDescriptor(id: "bluetooth-midi", name: "Bluetooth MIDI", category: .connectivity,
            description: "List Core MIDI sources and destinations, pair Bluetooth LE MIDI devices with Apple's pairing UI, and decode incoming MIDI messages live.", frameworks: ["CoreMIDI", "CoreAudioKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["A Bluetooth LE MIDI device (or any MIDI source)"], osRequirements: ["iOS 14+ · macOS 11+"], permissions: ["Bluetooth Usage Description"], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/coremidi")!, evaluate: { .available },
            useCase: ExperimentUseCase(id: "ble-midi", title: "Play into the toolbox", summary: "Pair a Bluetooth MIDI keyboard or controller and watch every note, controller and clock message arrive.", interaction: "Pair a device, start listening, then play: messages appear with channel, note name and raw UMP words."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "Core MIDI clients and ports cannot be created on \(CurrentPlatform.value.rawValue).", required: "iPhone, iPad or Mac",
                    nextStep: "Run the experiment on an iPhone, iPad or Mac."),
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
            description: "Range with a nearby iPhone over Ultra Wideband and see distance and direction live on a radar, with camera assistance, extended distance, convergence coaching and the accessory session boundary.", frameworks: ["NearbyInteraction", "MultipeerConnectivity", "ARKit (camera assistance)"], supportedPlatforms: [.iOS, .iPadOS, .watchOS], hardwareRequirements: ["UWB chip on both devices (iPhone 11 or later)", "Camera assistance and extended distance only where NIDeviceCapability reports support"], osRequirements: ["iOS 16+ · iPadOS 16+ · watchOS 9+", "Extended distance and peer capabilities: iOS 17+"], permissions: ["Nearby Interaction", "Local Network (token exchange)", "Camera (camera assistance)"], capabilities: ["Nearby Interaction", "Ultra Wideband"], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/nearbyinteraction")!, evaluate: ExperimentAvailability.nearbyInteraction,
            useCase: ExperimentUseCase(id: "uwb-finder", title: "Find the other iPhone",
                summary: "Point towards a second iPhone and watch the arrow and distance follow it in real time.",
                interaction: "Start peer ranging on two UWB iPhones with Apple Toolbox open. Turn on camera assistance and sweep the phone slowly until convergence reports converged."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "This device does not provide an Ultra Wideband chip (no iPad has one).", required: "iPhone 11 or later, or Apple Watch Series 6 or later",
                    nextStep: "Use two UWB-capable iPhones running Apple Toolbox."),
            ]),
    ]
}
