import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ExperimentCategory: String, CaseIterable, Identifiable, Sendable {
    case security = "Security"
    case location = "Location"
    case sensors = "Sensors"
    case input = "Input"
    case connectivity = "Connectivity"
    case networking = "Networking"
    case nfc = "NFC"
    case home = "Home"
    case camera = "Camera"
    case audio = "Audio"
    case ai = "AI"
    case maps = "Maps"
    case wallet = "Wallet"
    case developer = "Developer"

    var id: String { rawValue }
    var symbolName: String {
        switch self {
        case .security: "lock.shield"
        case .location: "location"
        case .sensors: "waveform.path.ecg"
        case .input: "gamecontroller"
        case .connectivity: "point.3.connected.trianglepath.dotted"
        case .networking: "network"
        case .nfc: "wave.3.right"
        case .home: "house"
        case .camera: "camera"
        case .audio: "waveform"
        case .ai: "sparkles"
        case .maps: "map"
        case .wallet: "wallet.pass"
        case .developer: "hammer"
        }
    }
}

enum SupportedPlatform: String, CaseIterable, Identifiable {
    case iOS = "iOS", iPadOS = "iPadOS", macOS = "macOS", watchOS = "watchOS", tvOS = "tvOS"
    var id: String { rawValue }
}

enum ExperimentStatus: Equatable {
    case available, permissionRequired, permissionDenied, entitlementRequired, approvalRequired
    case hardwareUnsupported, osUnsupported, platformUnsupported, regionRestricted
    case appleProgramRequired, developmentOnly, deviceOnly, simulatorOnly, unavailable

    var title: String {
        switch self {
        case .available: "Available"
        case .permissionRequired: "Permission Required"
        case .permissionDenied: "Permission Denied"
        case .entitlementRequired: "Entitlement Required"
        case .approvalRequired: "Approval Required"
        case .hardwareUnsupported: "Hardware Unsupported"
        case .osUnsupported: "OS Unsupported"
        case .platformUnsupported: "Platform Unsupported"
        case .regionRestricted: "Region Restricted"
        case .appleProgramRequired: "Apple Program Required"
        case .developmentOnly: "Development Only"
        case .deviceOnly: "Device Only"
        case .simulatorOnly: "Simulator Only"
        case .unavailable: "Unavailable"
        }
    }
}

struct ExperimentDescriptor: Identifiable {
    let id: String
    let name: String
    let category: ExperimentCategory
    let description: String
    let frameworks: [String]
    let supportedPlatforms: [SupportedPlatform]
    let hardwareRequirements: [String]
    let osRequirements: [String]
    let permissions: [String]
    let capabilities: [String]
    let entitlements: [String]
    let documentationURL: URL
    let evaluate: () -> ExperimentStatus

    var currentStatus: ExperimentStatus {
        supportedPlatforms.contains(CurrentPlatform.value) ? evaluate() : .platformUnsupported
    }
}

enum CurrentPlatform {
    static var value: SupportedPlatform {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPadOS : .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(tvOS)
        return .tvOS
        #else
        return .iOS
        #endif
    }
}

struct ExperimentResult: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let text: String
    let isError: Bool
}

struct ExperimentUseCase: Identifiable {
    let id: String
    let title: String
    let summary: String
    let interaction: String
}

enum ExperimentUseCaseCatalog {
    static let cryptoKit = ExperimentUseCase(id: "crypto-message", title: "Sign a message", summary: "Use CryptoKit to hash and sign text that you choose.", interaction: "Enter a message, then run hashing or signing and inspect the live output.")
    static let keychain = ExperimentUseCase(id: "keychain-value", title: "Store a secret", summary: "Use the Keychain as a small persistent credential store.", interaction: "Enter a value, save it, read it back, and delete it again.")
    static let secureEnclave = ExperimentUseCase(id: "secure-enclave-signature", title: "Sign with hardware-backed storage", summary: "Create a non-exportable Secure Enclave key and sign your own message.", interaction: "Enter a message and run the signing flow; the private key never leaves the enclave.")
    static let localAuthentication = ExperimentUseCase(id: "biometric-gate", title: "Protect an action", summary: "Use the device owner authentication policy before releasing a result.", interaction: "Run authentication and inspect the real biometric or passcode outcome.")

    static func forExperimentID(_ id: String) -> ExperimentUseCase? {
        switch id {
        case "cryptokit": cryptoKit
        case "keychain": keychain
        case "secure-enclave": secureEnclave
        case "localauthentication": localAuthentication
        case "core-location": ExperimentUseCase(id: "location-dashboard", title: "Build a live location dashboard", summary: "Use the device's real location stream, heading, and a geofence around you.", interaction: "Grant permission and start updates, then monitor a region around you and walk in or out to see entry and exit events. Upgrade to Always only if you want visits and significant changes.")
        case "core-motion": ExperimentUseCase(id: "motion-meter", title: "Move the device", summary: "Turn your iPhone or Apple Watch into a live motion meter.", interaction: "Start updates, tilt or move the device, and compare acceleration, rotation, and gravity vectors.")
        case "multipeer-connectivity": multipeerConnectivity
        case "game-controller": ExperimentUseCase(id: "controller-input-monitor", title: "Test a game controller", summary: "See which controllers the system reports and watch every button, trigger, and stick as you use it.", interaction: "Start monitoring, turn on or pair a controller (or use the Siri Remote on Apple TV), then press buttons and move the sticks.")
        default: ExperimentUseCase(
            id: "inspect-\(id)",
            title: "Try the real API",
            summary: "Run this experiment against the current device and inspect the result returned by Apple’s public framework.",
            interaction: "Use the action below to query availability or start the experiment. Unsupported and permission states remain visible."
        )
    }
    }

    static let multipeerConnectivity = ExperimentUseCase(
        id: "multipeer-messaging",
        title: "Nearby device messaging",
        summary: "Turn two Apple devices into a small local playground without a server or internet connection.",
        interaction: "Start discovery on both devices, accept the connection, then send a message between them."
    )
}
