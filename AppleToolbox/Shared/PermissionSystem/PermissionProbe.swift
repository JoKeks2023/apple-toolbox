import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(AVFoundation) && (os(iOS) || os(macOS))
import AVFoundation
#endif
#if canImport(Speech) && !os(watchOS) && !os(tvOS)
import Speech
#endif
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif
#if canImport(MusicKit)
import MusicKit
#endif
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

enum PermissionState: String {
    case notDetermined, granted, denied, restricted
    /// The system does not expose this state without prompting; the last known result is used when available.
    case unknown

    var experimentStatus: ExperimentStatus? {
        switch self {
        case .granted: nil
        case .notDetermined, .unknown: .permissionRequired
        case .denied, .restricted: .permissionDenied
        }
    }
}

/// Reads authorization states without ever triggering a permission prompt.
enum PermissionProbe {
    #if canImport(CoreLocation)
    /// One manager for authorization and accuracy reads; creating a CLLocationManager per read is expensive.
    /// Only read for status here (no delegate), so sharing it across isolation domains is safe.
    nonisolated(unsafe) static let locationManager = CLLocationManager()
    #endif

    static func location() -> PermissionState {
        #if canImport(CoreLocation)
        switch locationManager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        default: return .granted
        }
        #else
        return .unknown
        #endif
    }

    static func camera() -> PermissionState { captureAuthorization(video: true) }
    static func microphone() -> PermissionState { captureAuthorization(video: false) }

    private static func captureAuthorization(video: Bool) -> PermissionState {
        #if canImport(AVFoundation) && (os(iOS) || os(macOS))
        switch AVCaptureDevice.authorizationStatus(for: video ? .video : .audio) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .granted
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    static func speechRecognition() -> PermissionState {
        #if canImport(Speech) && !os(watchOS) && !os(tvOS)
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .granted
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    static func bluetooth() -> PermissionState {
        #if canImport(CoreBluetooth)
        switch CBManager.authorization {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .allowedAlways: return .granted
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    static func musicKit() -> PermissionState {
        #if canImport(MusicKit)
        switch MusicAuthorization.currentStatus {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .granted
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    static func motionActivity() -> PermissionState {
        #if canImport(CoreMotion) && (os(iOS) || os(watchOS))
        switch CMMotionActivityManager.authorizationStatus() {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .granted
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }

    // HomeKit, HealthKit and notification states cannot be read synchronously without prompting;
    // the experiments record the last result they observed.
    static func homeKit() -> PermissionState { remembered(.homeKit) }
    static func healthKit() -> PermissionState { remembered(.healthKit) }
    static func notifications() -> PermissionState { remembered(.notifications) }

    enum Remembered: String { case homeKit, healthKit, notifications }

    static func remember(_ state: PermissionState, for kind: Remembered) {
        UserDefaults.standard.set(state.rawValue, forKey: "permission.\(kind.rawValue)")
    }

    private static func remembered(_ kind: Remembered) -> PermissionState {
        UserDefaults.standard.string(forKey: "permission.\(kind.rawValue)").flatMap(PermissionState.init(rawValue:)) ?? .unknown
    }

    static func refreshNotificationState() async {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let state: PermissionState = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .granted
        @unknown default: .unknown
        }
        remember(state, for: .notifications)
        #endif
    }
}

/// Views observe this to re-evaluate experiment status after permissions change.
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()
    @Published private(set) var revision = 0

    func invalidate() { revision &+= 1 }

    /// Refreshes states that can only be read asynchronously, e.g. when the app becomes active again.
    func refresh() async {
        await PermissionProbe.refreshNotificationState()
        invalidate()
    }
}

/// Memoizes experiment status and pre-run checks per experiment id. Evaluators create system objects
/// (location managers, LAContext, speech recognizers, …), so they run once per `PermissionCenter.revision`
/// instead of on every render.
@MainActor
final class ExperimentStatusCache {
    static let shared = ExperimentStatusCache()

    private let center: PermissionCenter
    private var revision: Int?
    private var statuses: [String: ExperimentStatus] = [:]
    private var checks: [String: (status: ExperimentStatus, checks: [ExperimentCheck])] = [:]

    init(center: PermissionCenter = .shared) { self.center = center }

    func status(for experiment: ExperimentDescriptor) -> ExperimentStatus {
        dropIfStale()
        if let status = statuses[experiment.id] { return status }
        let status = experiment.uncachedStatus
        statuses[experiment.id] = status
        return status
    }

    func checks(for experiment: ExperimentDescriptor, status: ExperimentStatus) -> [ExperimentCheck] {
        dropIfStale()
        if let entry = checks[experiment.id], entry.status == status { return entry.checks }
        let result = experiment.uncachedChecks(for: status)
        checks[experiment.id] = (status, result)
        return result
    }

    private func dropIfStale() {
        guard revision != center.revision else { return }
        revision = center.revision
        statuses.removeAll(keepingCapacity: true)
        checks.removeAll(keepingCapacity: true)
    }
}
