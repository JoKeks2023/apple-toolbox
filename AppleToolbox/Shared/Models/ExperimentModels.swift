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
    case spatial = "Spatial"
    case audio = "Audio"
    case ai = "AI"
    case maps = "Maps"
    case wallet = "Wallet"
    case health = "Health"
    case system = "System"
    case platform = "Platform"
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
        case .spatial: "arkit"
        case .audio: "waveform"
        case .ai: "sparkles"
        case .maps: "map"
        case .wallet: "wallet.pass"
        case .health: "heart"
        case .system: "app.badge"
        case .platform: "desktopcomputer"
        case .developer: "hammer"
        }
    }
}

enum SupportedPlatform: String, CaseIterable, Identifiable {
    case iOS = "iOS", iPadOS = "iPadOS", macOS = "macOS", watchOS = "watchOS", tvOS = "tvOS"
    var id: String { rawValue }
}

enum ExperimentStatus: Hashable {
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
    let evaluate: @MainActor () -> ExperimentStatus
    /// What the user can try with this experiment (spec §3).
    var useCase: ExperimentUseCase? = nil
    /// Experiment-specific "Why doesn't this work?" texts; other statuses use the defaults.
    var explanations: [ExperimentStatus: ExperimentExplanation] = [:]
    /// Apple programs or agreements needed beyond the developer program (spec §5).
    var applePrograms: [String] = []

    var currentStatus: ExperimentStatus {
        guard supportedPlatforms.contains(CurrentPlatform.value) else { return .platformUnsupported }
        let status = evaluate()
        #if targetEnvironment(simulator)
        // The Simulator has no sensors, radios or Secure Enclave; the real device may well have them.
        if status == .hardwareUnsupported { return .deviceOnly }
        #endif
        return status
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

extension ExperimentUseCase {
    static func generic(for id: String) -> ExperimentUseCase {
        ExperimentUseCase(
            id: "inspect-\(id)",
            title: "Try the real API",
            summary: "Run this experiment against the current device and inspect the result returned by Apple’s public framework.",
            interaction: "Use the action below to query availability or start the experiment. Unsupported and permission states remain visible."
        )
    }
}

/// "Why doesn't this work?" (spec §38): reason, requirement and next step for an unavailable experiment.
struct ExperimentExplanation: Equatable {
    let reason: String
    let required: String
    let nextStep: String
}
