import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif

@MainActor
final class LocationExperimentService: NSObject, ObservableObject {
    @Published private(set) var authorization: String = "Not determined"
    @Published private(set) var status: ExperimentStatus = .permissionRequired
    @Published private(set) var output = "Ready to request location permission."
    @Published private(set) var isUpdating = false

    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    private var latestLocation: CLLocation?
    #if !os(tvOS)
    private var latestHeading: CLHeading?
    #endif
    #endif

    override init() {
        super.init()
        #if canImport(CoreLocation)
        manager.delegate = self
        updateAuthorization(manager.authorizationStatus)
        #endif
    }

    func requestPermission() {
        #if canImport(CoreLocation)
        manager.requestWhenInUseAuthorization()
        #else
        output = "Core Location is not available on this platform."
        #endif
    }

    func start() {
        #if canImport(CoreLocation) && !os(tvOS)
        #if os(macOS)
        let authorized = manager.authorizationStatus == .authorizedAlways
        #else
        let authorized = manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
        #endif
        guard authorized else {
            output = "Permission is required before live updates can start."
            requestPermission()
            return
        }
        isUpdating = true
        manager.startUpdatingLocation()
        #if !os(tvOS)
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        #endif
        #else
        output = "Core Location is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(CoreLocation) && !os(tvOS)
        manager.stopUpdatingLocation()
        #if !os(macOS)
        manager.stopUpdatingHeading()
        #endif
        #endif
        isUpdating = false
    }

    #if canImport(CoreLocation)
    private func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorization = switch status {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Authorized · Always"
        case .authorizedWhenInUse: "Authorized · When In Use"
        @unknown default: "Unknown"
        }
        self.status = switch status {
        case .authorizedAlways, .authorizedWhenInUse: .available
        case .denied, .restricted: .permissionDenied
        case .notDetermined: .permissionRequired
        @unknown default: .unavailable
        }
    }
    #endif
}

#if canImport(CoreLocation)
@MainActor extension LocationExperimentService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization(manager.authorizationStatus)
        if manager.authorizationStatus == .denied { output = "Location permission was denied in Settings." }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latestLocation = location
        let coordinate = String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
        #if os(tvOS)
        let heading: Double? = nil
        #else
        let heading = latestHeading.map { $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading }
        #endif
        output = "Coordinate: \(coordinate)\nAccuracy: \(location.horizontalAccuracy.formatted(.number.precision(.fractionLength(1)))) m\nAltitude: \(location.altitude.formatted(.number.precision(.fractionLength(1)))) m\nSpeed: \(location.speed >= 0 ? location.speed.formatted(.number.precision(.fractionLength(1))) + " m/s" : "Unknown")\nCourse: \(location.course >= 0 ? location.course.formatted(.number.precision(.fractionLength(1))) + "°" : "Unknown")\nHeading: \(heading.map { $0.formatted(.number.precision(.fractionLength(1))) + "°" } ?? "Unknown")"
    }

    #if !os(tvOS)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        latestHeading = newHeading
        guard let latestLocation else { return }
        locationManager(manager, didUpdateLocations: [latestLocation])
    }
    #endif

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        output = "Location error: \(error.localizedDescription)"
    }
}
#endif
