import Foundation
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif
#if canImport(CoreAI) && (os(iOS) || os(macOS))
import CoreAI
#endif

// MARK: - Availability of the iOS 27 AI features

/// Turns the facts an availability check gathers into an experiment status. Pure, so every branch is testable.
enum AIAvailabilityMapping {
    /// - Parameters:
    ///   - platformSupported: iOS, iPadOS or macOS. FoundationModels and Core AI import on tvOS and watchOS, but their API is unavailable there.
    ///   - frameworkInSDK: the module is part of this build's SDK (Core AI is missing from the iOS Simulator SDK).
    ///   - isSimulator: the build runs in the Simulator.
    ///   - osSupported: iOS 27 / macOS 27 or later.
    ///   - liveStatus: the device's status once everything above holds; only evaluated then.
    static func status(platformSupported: Bool, frameworkInSDK: Bool, isSimulator: Bool, osSupported: Bool,
                       liveStatus: () -> ExperimentStatus) -> ExperimentStatus {
        guard platformSupported else { return .platformUnsupported }
        guard frameworkInSDK else { return isSimulator ? .deviceOnly : .platformUnsupported }
        guard osSupported else { return .osUnsupported }
        return liveStatus()
    }

    /// Image prompts need an available on-device model that reports the vision capability.
    static func imageInputStatus(modelStatus: ExperimentStatus, supportsVision: Bool) -> ExperimentStatus {
        guard modelStatus == .available else { return modelStatus }
        return supportsVision ? .available : .unavailable
    }
}

/// Where one Foundation Models feature runs, as the API defines it.
nonisolated struct AIExecutionFact: Identifiable, Equatable, Sendable {
    enum Place: String, Sendable {
        case onDevice = "On device"
        case requiresOS = "Requires iOS 27"
        case unsupported = "Not supported here"
        case notUsed = "Not used"
    }

    let feature: String
    let place: Place
    let detail: String
    var id: String { feature }
}

nonisolated enum AIExecutionFacts {
    static let pccEntitlement = "com.apple.developer.private-cloud-compute"

    /// - Parameters:
    ///   - imageInput: nil below iOS 27, otherwise whether the on-device model reports the vision capability.
    ///   - visionToolsInSDK: `_Vision_FoundationModels` (BarcodeReaderTool, OCRTool) is in this build's SDK.
    ///   - pccProvisioned: the embedded profile contains the managed Private Cloud Compute entitlement.
    static func foundationModels(imageInput: Bool?, visionToolsInSDK: Bool, pccProvisioned: Bool) -> [AIExecutionFact] {
        var facts = [AIExecutionFact(feature: "Text prompts & guided generation", place: .onDevice,
                                     detail: "SystemLanguageModel runs on this device; prompts, tool output and responses are not sent to a server.")]
        switch imageInput {
        case nil:
            facts.append(AIExecutionFact(feature: "Image prompts", place: .requiresOS,
                                         detail: "Transcript.ImageAttachment and Attachment are new in the iOS 27 / macOS 27 FoundationModels."))
        case true?:
            facts.append(AIExecutionFact(feature: "Image prompts", place: .onDevice,
                                         detail: "The attached image is processed by the same on-device model (capability .vision)."))
        case false?:
            facts.append(AIExecutionFact(feature: "Image prompts", place: .unsupported,
                                         detail: "SystemLanguageModel.default.capabilities does not contain .vision on this device."))
        }
        facts.append(visionToolsInSDK
            ? AIExecutionFact(feature: "Vision tools (codes, text)", place: imageInput == nil ? .requiresOS : .onDevice,
                              detail: "BarcodeReaderTool and OCRTool run Vision requests on this device when the model calls them.")
            : AIExecutionFact(feature: "Vision tools (codes, text)", place: .unsupported,
                              detail: "_Vision_FoundationModels is not part of this build's SDK (it is missing from the iOS Simulator SDK)."))
        facts.append(AIExecutionFact(feature: "Private Cloud Compute", place: .notUsed, detail: pccProvisioned
            ? "The profile contains \(pccEntitlement), but Apple Toolbox only uses the on-device SystemLanguageModel. PrivateCloudComputeLanguageModel would need an internet connection."
            : "PrivateCloudComputeLanguageModel (iOS 27) needs an internet connection and the managed entitlement \(pccEntitlement), which this app's profile does not contain. Nothing is sent to Apple's servers."))
        return facts
    }
}

extension ExperimentAvailability {
    static var isOS27OrLater: Bool {
        if #available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, *) { true } else { false }
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Foundation Models image prompts: iOS / macOS 27 with an available model that reports `.vision`.
    static func foundationModelsImage() -> ExperimentStatus {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        return AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: true, isSimulator: isSimulator, osSupported: isOS27OrLater) {
            guard #available(iOS 27.0, macOS 27.0, *) else { return .osUnsupported }
            return AIAvailabilityMapping.imageInputStatus(modelStatus: foundationModels(),
                                                          supportsVision: SystemLanguageModel.default.capabilities.contains(.vision))
        }
        #else
        return AIAvailabilityMapping.status(platformSupported: false, frameworkInSDK: false, isSimulator: isSimulator, osSupported: isOS27OrLater) { .available }
        #endif
    }

    /// Core AI: iOS / macOS 27 in a device build with at least one compute unit kind.
    static func coreAI() -> ExperimentStatus {
        #if canImport(CoreAI) && (os(iOS) || os(macOS))
        return AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: true, isSimulator: isSimulator, osSupported: isOS27OrLater) {
            guard #available(iOS 27.0, macOS 27.0, *) else { return .osUnsupported }
            return ComputeUnitKind.availableKinds.isEmpty ? .hardwareUnsupported : .available
        }
        #elseif os(iOS) || os(macOS)
        return AIAvailabilityMapping.status(platformSupported: true, frameworkInSDK: false, isSimulator: isSimulator, osSupported: isOS27OrLater) { .available }
        #else
        return AIAvailabilityMapping.status(platformSupported: false, frameworkInSDK: false, isSimulator: isSimulator, osSupported: isOS27OrLater) { .available }
        #endif
    }
}
