import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ExperimentCategory: String, CaseIterable, Identifiable {
    case security = "Security"
    case location = "Location"
    case sensors = "Sensors"
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
    static let multipeerConnectivity = ExperimentUseCase(
        id: "multipeer-messaging",
        title: "Nearby device messaging",
        summary: "Turn two Apple devices into a small local playground without a server or internet connection.",
        interaction: "Start discovery on both devices, accept the connection, then send a message between them."
    )
}
