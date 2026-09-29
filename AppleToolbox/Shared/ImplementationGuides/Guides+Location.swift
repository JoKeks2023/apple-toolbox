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
    ]
}
