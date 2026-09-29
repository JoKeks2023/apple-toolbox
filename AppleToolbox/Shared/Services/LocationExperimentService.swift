import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif

struct LocationCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
}

struct LocationRegion: Equatable {
    let center: LocationCoordinate
    let radius: Double
}

struct LocationMonitorEvent: Identifiable {
    let id = UUID()
    let date: Date
    let symbol: String
    let title: String
    let detail: String
}

/// Whether a Core Location service exists here, with the reason shown next to it.
struct LocationFeature {
    let isAvailable: Bool
    let detail: String
}

@MainActor
final class LocationExperimentService: NSObject, ObservableObject {
    static let regionRadii: [Double] = [50, 100, 200, 500, 1_000]
    /// Key inside `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist.
    static let fullAccuracyPurposeKey = "LiveDashboard"

    @Published private(set) var authorization: String = "Not determined"
    @Published private(set) var accuracyAuthorization = "—"
    @Published private(set) var isAuthorized = false
    @Published private(set) var isAlwaysAuthorized = false
    @Published private(set) var isReducedAccuracy = false
    @Published private(set) var status: ExperimentStatus = .permissionRequired
    @Published private(set) var output = "Ready to request location permission."
    @Published private(set) var isUpdating = false
    @Published private(set) var coordinate = "—"
    @Published private(set) var accuracy = "—"
    @Published private(set) var altitude = "—"
    @Published private(set) var speed = "—"
    @Published private(set) var course = "—"
    @Published private(set) var heading = "—"
    @Published private(set) var floorLevel = "—"
    @Published private(set) var trueHeading = "—"
    @Published private(set) var magneticHeading = "—"
    @Published private(set) var headingAccuracy = "—"
    @Published private(set) var coordinateValue: LocationCoordinate?
    @Published private(set) var monitoredRegion: LocationRegion?
    @Published private(set) var regionState = "Not monitoring"
    @Published private(set) var isMonitoringVisits = false
    @Published private(set) var isMonitoringSignificantChanges = false
    @Published private(set) var events: [LocationMonitorEvent] = []

    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    private var latestLocation: CLLocation?
    #endif
    #if os(iOS) || os(macOS)
    private var lastRegionState: CLMonitor.Event.State?
    #endif
    #if os(iOS)
    private var serviceSession: CLServiceSession?
    #endif

    override init() {
        super.init()
        #if canImport(CoreLocation)
        manager.delegate = self
        updateAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        #endif
        #if os(iOS) || os(macOS)
        // Visits and significant changes survive relaunches; clear leftovers from a run that never reached stop().
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        #endif
    }

    var regionMonitoring: LocationFeature {
        #if os(iOS) || os(macOS)
        LocationFeature(isAvailable: true, detail: isAlwaysAuthorized ? "CLMonitor · Always granted" : "CLMonitor · events only while the app is in use")
        #else
        LocationFeature(isAvailable: false, detail: "CLMonitor is not available on this platform")
        #endif
    }

    var visits: LocationFeature {
        #if os(iOS) || os(macOS)
        LocationFeature(isAvailable: true, detail: isAlwaysAuthorized ? "Available · Always granted" : "Available · needs Always to deliver visits")
        #else
        LocationFeature(isAvailable: false, detail: "Not available on this platform")
        #endif
    }

    var significantChanges: LocationFeature {
        #if os(iOS) || os(macOS)
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            return LocationFeature(isAvailable: false, detail: "Not supported by this device")
        }
        return LocationFeature(isAvailable: true, detail: isAlwaysAuthorized ? "Available · Always granted" : "Available · needs Always to deliver updates")
        #else
        return LocationFeature(isAvailable: false, detail: "Not available on this platform")
        #endif
    }

    var headingService: LocationFeature {
        #if canImport(CoreLocation) && !os(tvOS)
        CLLocationManager.headingAvailable()
            ? LocationFeature(isAvailable: true, detail: "Magnetometer available")
            : LocationFeature(isAvailable: false, detail: "This device has no magnetometer")
        #else
        LocationFeature(isAvailable: false, detail: "Not available on this platform")
        #endif
    }

    var canRequestAlways: Bool {
        #if canImport(CoreLocation) && !os(tvOS)
        isAuthorized && !isAlwaysAuthorized
        #else
        false
        #endif
    }

    func requestPermission() {
        #if canImport(CoreLocation)
        manager.requestWhenInUseAuthorization()
        #else
        output = "Core Location is not available on this platform."
        #endif
    }

    /// Only on explicit user request: Always is never required silently.
    func requestAlwaysAuthorization() {
        #if canImport(CoreLocation) && !os(tvOS)
        manager.requestAlwaysAuthorization()
        output = "Requested the upgrade to Always. The system offers it only once; if no prompt appears, change it in Settings › Privacy & Security › Location Services."
        #else
        output = "Always authorization is not available on this platform."
        #endif
    }

    func requestTemporaryPreciseLocation() {
        #if canImport(CoreLocation)
        Task {
            do {
                try await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.fullAccuracyPurposeKey)
                updateAuthorization(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
                output = manager.accuracyAuthorization == .fullAccuracy
                    ? "Precise location granted temporarily. It expires after you stop using the app."
                    : "Precise location was not granted; readings stay approximate."
            } catch {
                output = "Temporary precise location failed: \(error.localizedDescription)"
            }
        }
        #else
        output = "Core Location is not available on this platform."
        #endif
    }

    func startUpdates() {
        #if canImport(CoreLocation) && !os(tvOS)
        guard isAuthorized else {
            output = "Permission is required before live updates can start."
            requestPermission()
            return
        }
        isUpdating = true
        output = "Waiting for the first location…"
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        #else
        output = "Live location updates are not available on this platform."
        #endif
    }

    func stopUpdates() {
        #if canImport(CoreLocation) && !os(tvOS)
        manager.stopUpdatingLocation()
        #if !os(macOS)
        manager.stopUpdatingHeading()
        #endif
        #endif
        isUpdating = false
        output = latestLocation == nil ? "Live updates stopped. No location received yet." : "Live updates stopped. Last reading is still shown below."
    }

    /// Stops every running location service (live updates, region, visits, significant changes).
    func stop() {
        if isUpdating { stopUpdates() }
        stopRegionMonitoring()
        stopVisitMonitoring()
        stopSignificantChanges()
    }

    // MARK: Region monitoring

    func startRegionMonitoring(radius: Double) {
        #if os(iOS) || os(macOS)
        guard monitoredRegion == nil else { return }
        guard isAuthorized else {
            output = "Location permission is required before a region can be monitored."
            requestPermission()
            return
        }
        guard let latestLocation else {
            output = "Start live updates first; the region is centered on your current location."
            return
        }
        let center = latestLocation.coordinate
        monitoredRegion = LocationRegion(center: LocationCoordinate(latitude: center.latitude, longitude: center.longitude), radius: radius)
        lastRegionState = nil
        regionState = "Waiting for the first event"
        #if os(iOS)
        serviceSession = CLServiceSession(authorization: .whenInUse)
        #endif
        Self.regionSubscriber = self
        Self.changeMonitor { monitor in
            for identifier in await monitor.identifiers { await monitor.remove(identifier) }
            await monitor.add(CLMonitor.CircularGeographicCondition(center: center, radius: radius), identifier: Self.regionIdentifier, assuming: .unknown)
        }
        record("circle.dashed", "Region monitoring started", "\(Self.radiusLabel(radius)) circle around \(coordinate)")
        output = isReducedAccuracy
            ? "Monitoring started, but location is approximate; CLMonitor may withhold events (shown as “approximate location”)."
            : "Monitoring a \(Self.radiusLabel(radius)) circle. Walk in or out to see entry and exit events."
        #else
        output = "Region monitoring with CLMonitor is not available on this platform."
        #endif
    }

    func stopRegionMonitoring() {
        #if os(iOS) || os(macOS)
        guard monitoredRegion != nil else { return }
        monitoredRegion = nil
        regionState = "Not monitoring"
        if Self.regionSubscriber === self { Self.regionSubscriber = nil }
        #if os(iOS)
        serviceSession?.invalidate()
        serviceSession = nil
        #endif
        Self.changeMonitor { await $0.remove(Self.regionIdentifier) }
        record("stop.circle", "Region monitoring stopped", "Condition removed from CLMonitor.")
        #endif
    }

    // MARK: Visits and significant changes

    func startVisitMonitoring() {
        #if os(iOS) || os(macOS)
        guard !isMonitoringVisits else { return }
        guard isAuthorized else { output = "Location permission is required first."; requestPermission(); return }
        manager.startMonitoringVisits()
        isMonitoringVisits = true
        record("mappin.and.ellipse", "Visit monitoring started", isAlwaysAuthorized
               ? "Always granted. Visits arrive after the system detects an arrival or departure, often minutes later."
               : "Only When In Use granted. Visits are an Always service; expect no events until you upgrade.")
        #else
        output = "Visit monitoring is not available on this platform."
        #endif
    }

    func stopVisitMonitoring() {
        #if os(iOS) || os(macOS)
        guard isMonitoringVisits else { return }
        manager.stopMonitoringVisits()
        isMonitoringVisits = false
        record("mappin.slash", "Visit monitoring stopped", "stopMonitoringVisits() called.")
        #endif
    }

    func startSignificantChanges() {
        #if os(iOS) || os(macOS)
        guard !isMonitoringSignificantChanges else { return }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            output = "This device does not support significant-change monitoring."
            return
        }
        guard isAuthorized else { output = "Location permission is required first."; requestPermission(); return }
        manager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = true
        record("antenna.radiowaves.left.and.right", "Significant-change monitoring started", isAlwaysAuthorized
               ? "Always granted. Updates arrive after roughly 500 m of movement."
               : "Only When In Use granted. This service is meant for Always; delivery is not guaranteed.")
        #else
        output = "Significant-change monitoring is not available on this platform."
        #endif
    }

    func stopSignificantChanges() {
        #if os(iOS) || os(macOS)
        guard isMonitoringSignificantChanges else { return }
        manager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantChanges = false
        record("antenna.radiowaves.left.and.right.slash", "Significant-change monitoring stopped", "stopMonitoringSignificantLocationChanges() called.")
        #endif
    }

    static func radiusLabel(_ radius: Double) -> String {
        radius >= 1_000 ? "\(number(radius / 1_000, digits: 0)) km" : "\(number(radius, digits: 0)) m"
    }

    // MARK: Updates

    private func record(_ symbol: String, _ title: String, _ detail: String, date: Date = Date()) {
        events.insert(LocationMonitorEvent(date: date, symbol: symbol, title: title, detail: detail), at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
    }

    private static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    #if canImport(CoreLocation)
    private func updateAuthorization(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
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
        isAlwaysAuthorized = status == .authorizedAlways
        isReducedAccuracy = isAuthorized && accuracy == .reducedAccuracy
        accuracyAuthorization = !isAuthorized ? "—" : accuracy == .fullAccuracy ? "Precise" : "Approximate"
        self.status = switch status {
        case .authorizedAlways, .authorizedWhenInUse: .available
        case .denied, .restricted: .permissionDenied
        case .notDetermined: .permissionRequired
        @unknown default: .unavailable
        }
    }

    fileprivate func apply(_ location: CLLocation) {
        latestLocation = location
        coordinate = String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
        coordinateValue = LocationCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        accuracy = location.horizontalAccuracy >= 0 ? Self.number(location.horizontalAccuracy) + " m" : "Unknown"
        altitude = Self.number(location.altitude) + " m"
        speed = location.speed >= 0 ? Self.number(location.speed) + " m/s" : "Unknown"
        course = location.course >= 0 ? Self.number(location.course) + "°" : "Unknown"
        floorLevel = location.floor.map { "Level \($0.level)" } ?? "Not reported (venue without indoor data)"
        if isMonitoringSignificantChanges && !isUpdating {
            record("location.circle", "Significant location change", "\(coordinate) · ±\(accuracy)", date: location.timestamp)
        }
        output = "Live location received at \(Date().formatted(date: .omitted, time: .standard))."
    }

    fileprivate func apply(_ reading: HeadingReading) {
        let magnetic = Self.number(reading.magneticHeading) + "°"
        let isValid = reading.accuracy >= 0
        trueHeading = reading.trueHeading >= 0 ? Self.number(reading.trueHeading) + "°" : "Invalid · needs a location fix"
        magneticHeading = isValid ? magnetic : "Invalid · calibrate the compass"
        headingAccuracy = isValid ? "±" + Self.number(reading.accuracy) + "°" : "Invalid · calibrate the compass"
        heading = reading.trueHeading >= 0 ? trueHeading + " true" : isValid ? magnetic + " magnetic" : "Unknown"
    }

    fileprivate func recordVisit(arrival: Date, departure: Date, coordinate: CLLocationCoordinate2D, accuracy: Double) {
        let time = { (date: Date) in date.formatted(date: .abbreviated, time: .shortened) }
        let arrived = arrival == .distantPast ? "unknown" : time(arrival)
        let departed = departure == .distantFuture ? "still there" : time(departure)
        let place = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        record("mappin.circle", departure == .distantFuture ? "Visit arrival" : "Visit departure",
               "Arrived \(arrived) · departed \(departed) · \(place) ±\(Self.number(accuracy, digits: 0)) m")
    }

    fileprivate func fail(_ message: String) {
        output = "Location error: \(message)"
    }
    #endif

    #if os(iOS) || os(macOS)
    private static let monitorName = "AppleToolboxRegion"
    private static let regionIdentifier = "around-current-location"
    private static var monitorLoader: Task<CLMonitor, Never>?
    private static var pendingMonitorChange: Task<Void, Never>?
    private static weak var regionSubscriber: LocationExperimentService?

    /// Only one `CLMonitor` per name may be open, so the app keeps one instance with one event consumer
    /// and forwards events to the run view that is currently monitoring.
    private static func sharedMonitor() async -> CLMonitor {
        if let monitorLoader { return await monitorLoader.value }
        let loader = Task { @MainActor in
            let monitor = await CLMonitor(monitorName)
            Task { @MainActor in
                do {
                    for try await event in await monitor.events { regionSubscriber?.handleRegionEvent(event) }
                } catch {
                    regionSubscriber?.fail("Region monitoring ended: \(error.localizedDescription)")
                }
                monitorLoader = nil
            }
            return monitor
        }
        monitorLoader = loader
        return await loader.value
    }

    /// Serializes changes so a quick stop/start cannot remove the condition that was just added.
    private static func changeMonitor(_ change: @escaping @MainActor (CLMonitor) async -> Void) {
        let previous = pendingMonitorChange
        pendingMonitorChange = Task { @MainActor in
            await previous?.value
            await change(await sharedMonitor())
        }
    }

    private func handleRegionEvent(_ event: CLMonitor.Event) {
        guard monitoredRegion != nil, event.identifier == Self.regionIdentifier else { return }
        let symbol: String, title: String
        switch event.state {
        case .satisfied:
            regionState = "Inside"
            symbol = "arrow.down.right.circle"
            title = lastRegionState == .unsatisfied ? "Entered region" : "Inside region"
        case .unsatisfied:
            regionState = "Outside"
            symbol = "arrow.up.left.circle"
            title = lastRegionState == .satisfied ? "Exited region" : "Outside region"
        case .unmonitored:
            regionState = "Not monitored"
            symbol = "exclamationmark.circle"
            title = "Condition not monitored"
        default:
            regionState = "Unknown"
            symbol = "questionmark.circle"
            title = "Region state unknown"
        }
        lastRegionState = event.state
        let suspended = Self.suspensionReasons(of: event)
        record(symbol, title, suspended.isEmpty ? "State: \(regionState)" : "State: \(regionState) · suspended: \(suspended.joined(separator: ", "))", date: event.date)
    }

    private static func suspensionReasons(of event: CLMonitor.Event) -> [String] {
        [
            (event.authorizationDenied, "authorization denied"),
            (event.authorizationDeniedGlobally, "Location Services off"),
            (event.authorizationRestricted, "restricted"),
            (event.insufficientlyInUse, "app not in use"),
            (event.accuracyLimited, "approximate location"),
            (event.conditionUnsupported, "condition unsupported"),
            (event.conditionLimitExceeded, "too many conditions"),
            (event.persistenceUnavailable, "persistence unavailable"),
            (event.serviceSessionRequired, "service session required"),
            (event.authorizationRequestInProgress, "permission prompt open"),
        ].filter(\.0).map(\.1)
    }
    #endif
}

#if canImport(CoreLocation)
private struct HeadingReading: Sendable {
    let trueHeading: Double
    let magneticHeading: Double
    let accuracy: Double
}

// Core Location calls back on the thread that created the manager (main); values are still copied
// before hopping to the main actor so the conformance stays nonisolated.
extension LocationExperimentService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor [weak self] in
            guard let self else { return }
            updateAuthorization(status, accuracy: accuracy)
            PermissionCenter.shared.invalidate()
            if status == .denied { output = "Location permission was denied in Settings." }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in self?.apply(location) }
    }

    #if !os(tvOS)
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let reading = HeadingReading(trueHeading: newHeading.trueHeading, magneticHeading: newHeading.magneticHeading, accuracy: newHeading.headingAccuracy)
        Task { @MainActor [weak self] in self?.apply(reading) }
    }
    #endif

    #if os(iOS) || os(macOS)
    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let arrival = visit.arrivalDate, departure = visit.departureDate
        let coordinate = visit.coordinate, accuracy = visit.horizontalAccuracy
        Task { @MainActor [weak self] in self?.recordVisit(arrival: arrival, departure: departure, coordinate: coordinate, accuracy: accuracy) }
    }
    #endif

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.fail(message) }
    }
}
#endif
