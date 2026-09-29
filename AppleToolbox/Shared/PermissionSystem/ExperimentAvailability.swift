import Foundation
#if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
import LocalAuthentication
#endif
#if canImport(CoreNFC) && os(iOS)
import CoreNFC
#endif
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif
#if canImport(NearbyInteraction) && (os(iOS) || os(watchOS))
import NearbyInteraction
#endif
#if canImport(ARKit) && os(iOS)
import ARKit
#endif
#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif
#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity
#endif
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif
#if canImport(HealthKit) && (os(iOS) || os(watchOS))
import HealthKit
#endif
#if canImport(PassKit) && !os(watchOS) && !os(tvOS)
import PassKit
#endif
#if canImport(DeviceCheck)
import DeviceCheck
#endif
#if canImport(Speech) && !os(watchOS) && !os(tvOS)
import Speech
#endif

/// Live status checks used by the experiment registry. They combine hardware support with the
/// current authorization state and never prompt the user.
enum ExperimentAvailability {
    static func localAuthentication() -> ExperimentStatus {
        #if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return .available }
        return error?.code == LAError.passcodeNotSet.rawValue ? .unavailable : .hardwareUnsupported
        #else
        return .platformUnsupported
        #endif
    }

    static func location() -> ExperimentStatus {
        PermissionProbe.location().experimentStatus ?? .available
    }

    static func nfc() -> ExperimentStatus {
        #if canImport(CoreNFC) && os(iOS)
        NFCNDEFReaderSession.readingAvailable ? .available : .hardwareUnsupported
        #else
        .platformUnsupported
        #endif
    }

    static func bluetooth() -> ExperimentStatus {
        PermissionProbe.bluetooth().experimentStatus ?? .available
    }

    #if canImport(AVFoundation) && (os(iOS) || os(macOS))
    /// Capture hardware presence, read once instead of on every status evaluation.
    private static let hasCamera = AVCaptureDevice.default(for: .video) != nil
    private static let hasMicrophone = AVCaptureDevice.default(for: .audio) != nil
    #endif

    static func camera() -> ExperimentStatus {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard hasCamera else { return .hardwareUnsupported }
        return PermissionProbe.camera().experimentStatus ?? .available
        #else
        return .platformUnsupported
        #endif
    }

    static func microphone() -> ExperimentStatus {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard hasMicrophone else { return .hardwareUnsupported }
        return PermissionProbe.microphone().experimentStatus ?? .available
        #else
        return .platformUnsupported
        #endif
    }

    static func speech() -> ExperimentStatus {
        #if canImport(Speech) && !os(watchOS) && !os(tvOS)
        if let status = PermissionProbe.speechRecognition().experimentStatus { return status }
        if let status = PermissionProbe.microphone().experimentStatus { return status }
        return SFSpeechRecognizer()?.isAvailable == true ? .available : .unavailable
        #else
        return .platformUnsupported
        #endif
    }

    static func homeKit() -> ExperimentStatus {
        PermissionProbe.homeKit().experimentStatus ?? .available
    }

    static func healthKit() -> ExperimentStatus {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        guard HKHealthStore.isHealthDataAvailable() else { return .hardwareUnsupported }
        return PermissionProbe.healthKit().experimentStatus ?? .available
        #else
        return .platformUnsupported
        #endif
    }

    static func musicKit() -> ExperimentStatus {
        PermissionProbe.musicKit().experimentStatus ?? .available
    }

    static func notifications() -> ExperimentStatus {
        PermissionProbe.notifications().experimentStatus ?? .available
    }

    static func watchConnectivity() -> ExperimentStatus {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        WCSession.isSupported() ? .available : .hardwareUnsupported
        #else
        .platformUnsupported
        #endif
    }

    static func nearbyInteraction() -> ExperimentStatus {
        #if canImport(NearbyInteraction) && (os(iOS) || os(watchOS))
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement ? .available : .hardwareUnsupported
        #else
        .platformUnsupported
        #endif
    }

    static func arKit() -> ExperimentStatus {
        #if canImport(ARKit) && os(iOS)
        guard ARWorldTrackingConfiguration.isSupported else { return .hardwareUnsupported }
        return PermissionProbe.camera().experimentStatus ?? .available
        #else
        return .platformUnsupported
        #endif
    }

    static func roomPlan() -> ExperimentStatus {
        #if canImport(RoomPlan) && os(iOS)
        guard RoomCaptureSession.isSupported else { return .hardwareUnsupported }
        return PermissionProbe.camera().experimentStatus ?? .available
        #else
        return .platformUnsupported
        #endif
    }

    static func foundationModels() -> ExperimentStatus {
        #if canImport(FoundationModels) && (os(iOS) || os(macOS))
        switch SystemLanguageModel.default.availability {
        case .available:
            return AppleIntelligenceRegionMapping.status(modelStatus: .available,
                                                         supportsCurrentLocale: SystemLanguageModel.default.supportsLocale(Locale.current))
        case .unavailable(.deviceNotEligible): return .hardwareUnsupported
        case .unavailable: return .unavailable
        }
        #else
        return .platformUnsupported
        #endif
    }

    static func wallet() -> ExperimentStatus {
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        PKPassLibrary.isPassLibraryAvailable() ? .available : .unavailable
        #else
        .platformUnsupported
        #endif
    }

    static func appAttest() -> ExperimentStatus {
        #if canImport(DeviceCheck)
        DCAppAttestService.shared.isSupported ? .available : .hardwareUnsupported
        #else
        .platformUnsupported
        #endif
    }
}
