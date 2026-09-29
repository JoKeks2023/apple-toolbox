import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif

/// The beacon identity the user wants to range: a proximity UUID, optionally narrowed by major and minor.
nonisolated struct BeaconIdentity: Equatable, Sendable {
    let uuid: UUID
    let major: UInt16?
    let minor: UInt16?

    enum InputError: Error, Equatable {
        case invalidUUID, invalidMajor, invalidMinor, minorWithoutMajor

        var message: String {
            switch self {
            case .invalidUUID: "The proximity UUID must look like E2C56DB5-DFFB-48D2-B060-D0F5A71096E0 (32 hex digits in 8-4-4-4-12 groups)."
            case .invalidMajor: "Major must be a whole number from 0 to 65535, or empty to match every major."
            case .invalidMinor: "Minor must be a whole number from 0 to 65535, or empty to match every minor."
            case .minorWithoutMajor: "A minor value can only be matched together with a major value (CLBeaconIdentityConstraint has no UUID + minor form)."
            }
        }
    }

    /// Validates the text fields; empty major/minor fields mean "any".
    static func parse(uuid: String, major: String, minor: String) -> Result<BeaconIdentity, InputError> {
        guard let parsedUUID = UUID(uuidString: uuid.trimmingCharacters(in: .whitespacesAndNewlines)) else { return .failure(.invalidUUID) }
        let majorText = major.trimmingCharacters(in: .whitespacesAndNewlines)
        let minorText = minor.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedMajor: UInt16?
        var parsedMinor: UInt16?
        if !majorText.isEmpty {
            guard let value = UInt16(majorText) else { return .failure(.invalidMajor) }
            parsedMajor = value
        }
        if !minorText.isEmpty {
            guard let value = UInt16(minorText) else { return .failure(.invalidMinor) }
            guard parsedMajor != nil else { return .failure(.minorWithoutMajor) }
            parsedMinor = value
        }
        return .success(BeaconIdentity(uuid: parsedUUID, major: parsedMajor, minor: parsedMinor))
    }

    var summary: String {
        "\(uuid.uuidString) · major \(major.map(String.init) ?? "any") · minor \(minor.map(String.init) ?? "any")"
    }
}

/// Default proximity UUIDs of Apple's AirLocate sample and common beacon vendors, for quick testing.
nonisolated enum BeaconUUIDPreset: String, CaseIterable, Identifiable, Sendable {
    case custom, airLocate, estimote, kontakt, radiusNetworks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: "Custom UUID"
        case .airLocate: "Apple AirLocate sample"
        case .estimote: "Estimote default"
        case .kontakt: "Kontakt.io default"
        case .radiusNetworks: "Radius Networks default"
        }
    }

    var uuid: String? {
        switch self {
        case .custom: nil
        case .airLocate: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"
        case .estimote: "B9407F30-F5F8-466E-AFF9-25556B57FE6D"
        case .kontakt: "F7826DA6-4FA2-4E98-8024-BC5B71E0893E"
        case .radiusNetworks: "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6"
        }
    }
}

nonisolated enum BeaconProximity: String, Sendable {
    case immediate = "Immediate", near = "Near", far = "Far", unknown = "Unknown"

    var symbol: String {
        switch self {
        case .immediate: "dot.radiowaves.left.and.right"
        case .near: "wifi"
        case .far: "wifi.exclamationmark"
        case .unknown: "questionmark.circle"
        }
    }
}

/// One ranged beacon, copied out of `CLBeacon` so it can cross to the main actor.
nonisolated struct BeaconReading: Identifiable, Equatable, Sendable {
    let uuid: UUID
    let major: Int
    let minor: Int
    let proximity: BeaconProximity
    /// Estimated distance in meters derived from RSSI; negative when Core Location cannot estimate it.
    let accuracy: Double
    /// Received signal strength in dBm; 0 when the last ranging interval had no measurement.
    let rssi: Int
    let timestamp: Date

    var id: String { "\(uuid.uuidString)-\(major)-\(minor)" }

    var accuracyText: String { accuracy < 0 ? "Unknown" : "±" + accuracy.formatted(.number.precision(.fractionLength(2))) + " m" }
    var rssiText: String { rssi == 0 ? "No reading" : "\(rssi) dBm" }

    /// Nearest first; beacons without a distance estimate go last.
    static func sortedByDistance(_ readings: [BeaconReading]) -> [BeaconReading] {
        readings.sorted { lhs, rhs in
            switch (lhs.accuracy < 0, rhs.accuracy < 0) {
            case (false, true): true
            case (true, false): false
            case (true, true): lhs.rssi > rhs.rssi
            case (false, false): lhs.accuracy < rhs.accuracy
            }
        }
    }
}

#if os(iOS) || os(macOS)
extension BeaconReading {
    nonisolated init(_ beacon: CLBeacon) {
        uuid = beacon.uuid
        major = beacon.major.intValue
        minor = beacon.minor.intValue
        proximity = switch beacon.proximity {
        case .immediate: .immediate
        case .near: .near
        case .far: .far
        default: .unknown
        }
        accuracy = beacon.accuracy
        rssi = beacon.rssi
        timestamp = beacon.timestamp
    }
}

extension BeaconIdentity {
    var constraint: CLBeaconIdentityConstraint {
        switch (major, minor) {
        case let (major?, minor?): CLBeaconIdentityConstraint(uuid: uuid, major: major, minor: minor)
        case let (major?, nil): CLBeaconIdentityConstraint(uuid: uuid, major: major)
        default: CLBeaconIdentityConstraint(uuid: uuid)
        }
    }
}
#endif

/// Ranges iBeacons that match a user-entered identity with `CLLocationManager.startRangingBeacons(satisfying:)`.
@MainActor
final class BeaconRangingService: NSObject, ObservableObject {
    @Published var preset: BeaconUUIDPreset = .airLocate
    @Published var uuidText = BeaconUUIDPreset.airLocate.uuid ?? ""
    @Published var majorText = ""
    @Published var minorText = ""
    @Published private(set) var authorization = "Not determined"
    @Published private(set) var isAuthorized = false
    @Published private(set) var isRanging = false
    @Published private(set) var isWaitingForPermission = false
    @Published private(set) var activeIdentity: BeaconIdentity?
    @Published private(set) var beacons: [BeaconReading] = []
    @Published private(set) var distinctBeacons = 0
    @Published private(set) var callbackCount = 0
    @Published private(set) var lastCallback: Date?
    @Published private(set) var isError = false
    @Published private(set) var output = "Enter the proximity UUID your beacons advertise, then start ranging."

    private var seenBeaconIDs: Set<String> = []
    #if os(iOS) || os(macOS)
    private let manager = CLLocationManager()
    private var activeConstraint: CLBeaconIdentityConstraint?
    #endif

    override init() {
        super.init()
        #if os(iOS) || os(macOS)
        manager.delegate = self
        updateAuthorization(manager.authorizationStatus)
        #endif
    }

    var rangingAvailability: String {
        #if os(iOS) || os(macOS)
        CLLocationManager.isRangingAvailable() ? "Available on this device" : "Not available (CLLocationManager.isRangingAvailable() is false)"
        #else
        "Not available on this platform"
        #endif
    }

    func applyPreset(_ preset: BeaconUUIDPreset) {
        if let uuid = preset.uuid { uuidText = uuid }
    }

    func start() {
        #if os(iOS) || os(macOS)
        guard !isRanging else { return }
        let identity: BeaconIdentity
        switch BeaconIdentity.parse(uuid: uuidText, major: majorText, minor: minorText) {
        case .success(let parsed): identity = parsed
        case .failure(let error):
            isError = true
            output = error.message
            return
        }
        guard CLLocationManager.isRangingAvailable() else {
            isError = true
            output = "CLLocationManager.isRangingAvailable() returned false: this device cannot range iBeacons (no Bluetooth LE or ranging is disabled)."
            return
        }
        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted else {
            isError = true
            output = "Location access is \(authorization.lowercased()). Beacon ranging is a location service; allow Apple Toolbox in Settings › Privacy & Security › Location Services."
            return
        }
        guard isAuthorized else {
            activeIdentity = identity
            isWaitingForPermission = true
            isError = false
            output = "Beacon ranging is a location service. Waiting for location permission…"
            manager.requestWhenInUseAuthorization()
            return
        }
        beginRanging(identity)
        #else
        isError = true
        output = "Beacon ranging is not available on this platform."
        #endif
    }

    func stop() {
        #if os(iOS) || os(macOS)
        if let activeConstraint { manager.stopRangingBeacons(satisfying: activeConstraint) }
        activeConstraint = nil
        #endif
        let wasRanging = isRanging
        isRanging = false
        isWaitingForPermission = false
        if wasRanging {
            output = "Ranging stopped after \(callbackCount) callback(s); \(distinctBeacons) distinct beacon(s) seen."
        }
    }

    #if os(iOS) || os(macOS)
    private func beginRanging(_ identity: BeaconIdentity) {
        let constraint = identity.constraint
        activeIdentity = identity
        activeConstraint = constraint
        isWaitingForPermission = false
        isRanging = true
        isError = false
        beacons = []
        seenBeaconIDs = []
        distinctBeacons = 0
        callbackCount = 0
        lastCallback = nil
        manager.startRangingBeacons(satisfying: constraint)
        output = "Ranging \(identity.summary)\nCore Location reports matching beacons about once per second."
    }

    private func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorization = switch status {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Authorized · Always"
        case .authorizedWhenInUse: "Authorized · When In Use"
        @unknown default: "Unknown"
        }
        #if os(macOS)
        isAuthorized = status == .authorizedAlways
        #else
        isAuthorized = status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
    }

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        updateAuthorization(status)
        PermissionCenter.shared.invalidate()
        guard isWaitingForPermission, let identity = activeIdentity else { return }
        if isAuthorized {
            beginRanging(identity)
        } else if status == .denied || status == .restricted {
            isWaitingForPermission = false
            isError = true
            output = "Location access is \(authorization.lowercased()). Beacon ranging needs it; allow Apple Toolbox in Settings › Privacy & Security › Location Services."
        }
    }

    fileprivate func apply(_ readings: [BeaconReading]) {
        guard isRanging else { return }
        callbackCount += 1
        lastCallback = Date()
        beacons = BeaconReading.sortedByDistance(readings)
        seenBeaconIDs.formUnion(readings.map(\.id))
        distinctBeacons = seenBeaconIDs.count
        if readings.isEmpty && callbackCount == 1 {
            output = "Ranging is running, but no beacon with this identity is in range yet."
        } else if !readings.isEmpty {
            output = "\(readings.count) beacon(s) in range · callback #\(callbackCount)"
        }
    }

    fileprivate func rangingFailed(_ message: String) {
        isError = true
        output = "Ranging failed: \(message)"
        if let activeConstraint { manager.stopRangingBeacons(satisfying: activeConstraint) }
        activeConstraint = nil
        isRanging = false
    }
    #endif
}

#if os(iOS) || os(macOS)
// The manager is created on the main thread, so Core Location calls back there; values are copied
// into Sendable readings before hopping to the main actor so the conformance stays nonisolated.
extension BeaconRangingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        let readings = beacons.map(BeaconReading.init)
        Task { @MainActor [weak self] in self?.apply(readings) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: Error) {
        let nsError = error as NSError
        let message = "\(error.localizedDescription) (\(nsError.domain) code \(nsError.code))"
        Task { @MainActor [weak self] in self?.rangingFailed(message) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        // kCLErrorLocationUnknown is transient; everything else is reported.
        guard nsError.code != CLError.locationUnknown.rawValue else { return }
        let message = "\(error.localizedDescription) (\(nsError.domain) code \(nsError.code))"
        Task { @MainActor [weak self] in self?.rangingFailed(message) }
    }
}
#endif

extension ExperimentAvailability {
    /// Ranging needs Bluetooth LE hardware that Core Location can use, plus location authorization.
    static func beaconRanging() -> ExperimentStatus {
        #if os(iOS) || os(macOS)
        guard CLLocationManager.isRangingAvailable() else { return .hardwareUnsupported }
        return location()
        #else
        return .platformUnsupported
        #endif
    }
}
