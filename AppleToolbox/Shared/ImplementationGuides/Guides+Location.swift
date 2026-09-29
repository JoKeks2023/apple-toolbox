import Foundation

nonisolated extension ImplementationGuides {
    static let location: [String: ImplementationGuide] = [
        "core-location": ImplementationGuide(
            snippet: #"""
            import CoreLocation

            /// Streams location updates while the app is in use.
            @MainActor
            final class LocationReader {
                private let manager = CLLocationManager()
                private var task: Task<Void, Never>?

                func start(onUpdate: @escaping (CLLocation) -> Void) {
                    manager.requestWhenInUseAuthorization()
                    task = Task {
                        do {
                            for try await update in CLLocationUpdate.liveUpdates() {
                                if let location = update.location { onUpdate(location) }
                            }
                        } catch {
                            print("Location updates ended: \(error)")
                        }
                    }
                }

                func stop() { task?.cancel() }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocationWhenInUseUsageDescription", value: "Shows where you are while you use the app."),
            ],
            notes: [
                "CLLocationUpdate.liveUpdates() (iOS 17+) replaces the delegate for most apps; cancel the task to stop.",
                "Precise vs. approximate location is the user's choice: check accuracyAuthorization before relying on it.",
                "Background updates also need NSLocationAlwaysAndWhenInUseUsageDescription and the location background mode.",
            ]
        ),
        "ibeacon-ranging": ImplementationGuide(
            snippet: #"""
            import CoreLocation

            /// Ranges iBeacons with a given UUID and reports the nearest one.
            @MainActor
            final class BeaconRanger: NSObject, @preconcurrency CLLocationManagerDelegate {
                private let manager = CLLocationManager() // created on main, so callbacks arrive on main
                private let constraint = CLBeaconIdentityConstraint(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!)

                func start() {
                    manager.delegate = self
                    manager.requestWhenInUseAuthorization()
                }

                func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
                    guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways,
                          CLLocationManager.isRangingAvailable() else { return }
                    manager.startRangingBeacons(satisfying: constraint)
                }

                func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                                     satisfying constraint: CLBeaconIdentityConstraint) {
                    guard let nearest = beacons.first(where: { $0.proximity != .unknown }) else { return }
                    print("Beacon \(nearest.major)/\(nearest.minor): \(nearest.accuracy) m, RSSI \(nearest.rssi)")
                }

                func stop() { manager.stopRangingBeacons(satisfying: constraint) }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocationWhenInUseUsageDescription", value: "Finds nearby beacons in the store."),
            ],
            notes: [
                "Ranging only works in the foreground; use CLMonitor with a BeaconIdentityCondition to be woken on region entry.",
                "You must know the beacon UUID — iOS never exposes iBeacons through Core Bluetooth scans.",
                "accuracy is a rough RSSI-based estimate in metres; smooth it before showing distances.",
            ]
        ),
        "location-dashboard": ImplementationGuide(
            snippet: #"""
            import CoreLocation
            import MapKit
            import SwiftUI

            /// Map plus live accuracy, speed and altitude from CLLocationUpdate.
            struct LocationDashboard: View {
                @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
                @State private var location: CLLocation?

                var body: some View {
                    VStack {
                        Map(position: $position) { UserAnnotation() }
                        if let location {
                            Text("±\(Int(location.horizontalAccuracy)) m · \(max(location.speed, 0), format: .number.precision(.fractionLength(1))) m/s · \(Int(location.altitude)) m")
                                .monospacedDigit()
                        }
                    }
                    .task {
                        // Holding a service session asks for When In Use authorization (iOS 18+).
                        let session = CLServiceSession(authorization: .whenInUse)
                        defer { session.invalidate() }
                        do {
                            for try await update in CLLocationUpdate.liveUpdates() {
                                if let newLocation = update.location { location = newLocation }
                            }
                        } catch {
                            print("Updates ended: \(error)")
                        }
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocationWhenInUseUsageDescription", value: "Shows your position, speed and altitude."),
                .init(key: "NSLocationTemporaryUsageDescriptionDictionary", value: "<dict><key>PreciseDashboard</key><string>Precise location makes the accuracy readings meaningful.</string></dict>"),
            ],
            notes: [
                "speed and course are -1 when invalid; check speedAccuracy/courseAccuracy before displaying them.",
                "With approximate location, ask for precision temporarily via CLServiceSession(authorization:fullAccuracyPurposeKey:).",
                "The .task modifier cancels the update loop automatically when the view disappears.",
            ]
        ),
    ]
}
