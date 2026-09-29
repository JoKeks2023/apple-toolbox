import Foundation

nonisolated extension ImplementationGuides {
    static let maps: [String: ImplementationGuide] = [
        "mapkit-search": ImplementationGuide(
            snippet: #"""
            import MapKit

            /// Searches points of interest near a region with MKLocalSearch.
            func searchPlaces(_ query: String, near center: CLLocationCoordinate2D) async throws -> [MKMapItem] {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = MKCoordinateRegion(center: center, latitudinalMeters: 5_000, longitudinalMeters: 5_000)
                request.resultTypes = [.pointOfInterest, .address]

                let response = try await MKLocalSearch(request: request).start()
                for item in response.mapItems {
                    print(item.name ?? "Unnamed", item.location.coordinate.latitude, item.location.coordinate.longitude)
                }
                return response.mapItems
            }
            """#,
            notes: [
                "MapKit search needs no permission or entitlement, but it does need a network connection.",
                "For search-as-you-type use MKLocalSearchCompleter and run MKLocalSearch only for the chosen completion.",
                "Apple throttles searches per device; debounce user input.",
            ]
        ),
        "indoor-imdf": ImplementationGuide(
            snippet: #"""
            import MapKit

            /// Decodes an IMDF archive's unit.geojson and groups the room shapes by level id.
            func unitsByLevel(inArchive folder: URL) throws -> [String: [any MKOverlay]] {
                let data = try Data(contentsOf: folder.appending(path: "unit.geojson"))
                var units: [String: [any MKOverlay]] = [:]

                for case let feature as MKGeoJSONFeature in try MKGeoJSONDecoder().decode(data) {
                    guard let json = feature.properties,
                          let properties = try JSONSerialization.jsonObject(with: json) as? [String: Any],
                          let level = properties["level_id"] as? String else { continue }
                    units[level, default: []] += feature.geometry.compactMap { $0 as? any MKOverlay }
                }
                return units
            }

            /// Draw the overlays of one level; return this from mapView(_:rendererFor:).
            func renderer(for overlay: any MKOverlay) -> MKOverlayRenderer {
                guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = .systemTeal.withAlphaComponent(0.2)
                renderer.strokeColor = .systemTeal
                renderer.lineWidth = 1
                return renderer
            }
            """#,
            notes: [
                "Files from fileImporter are security-scoped: wrap reads in startAccessingSecurityScopedResource() / stop….",
                "IMDF feature properties are raw JSON Data; decode them with JSONSerialization or a Codable type.",
                "Show one level at a time (level.geojson has the ordinal) and filter units, openings and amenities by level_id.",
            ]
        ),
        "indoor-survey": ImplementationGuide(
            snippet: #"""
            import CoreLocation

            struct SurveySample: Codable, Sendable {
                let latitude, longitude, horizontalAccuracy: Double
                let floor: Int?
                let timestamp: Date
            }

            /// Records location samples with their accuracy and floor, then exports them as JSON.
            @MainActor
            final class Surveyor {
                private let manager = CLLocationManager()
                private(set) var samples: [SurveySample] = []

                func record(count: Int = 20) async throws {
                    manager.requestWhenInUseAuthorization()
                    if manager.accuracyAuthorization == .reducedAccuracy {
                        // The key must exist in NSLocationTemporaryUsageDescriptionDictionary.
                        try await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "IndoorSurvey")
                    }
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        guard let location = update.location else { continue }
                        samples.append(SurveySample(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                                    horizontalAccuracy: location.horizontalAccuracy,
                                                    floor: location.floor?.level, timestamp: location.timestamp))
                        if samples.count >= count { break }
                    }
                }

                func export(to url: URL) throws {
                    try JSONEncoder().encode(samples).write(to: url, options: .atomic)
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocationWhenInUseUsageDescription", value: "Measures location accuracy on each floor of the venue."),
                .init(key: "NSLocationTemporaryUsageDescriptionDictionary",
                      value: "<dict>\n<key>IndoorSurvey</key>\n<string>Precise location is needed to measure indoor accuracy.</string>\n</dict>"),
                .init(key: "UIFileSharingEnabled", value: "<true/>"),
                .init(key: "LSSupportsOpeningDocumentsInPlace", value: "<true/>"),
            ],
            notes: [
                "CLLocation.floor is only set in venues Apple has mapped indoors; expect nil elsewhere.",
                "UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace make the Documents folder visible in the Files app.",
                "Compare horizontalAccuracy with the measured error against a known reference point; the two often differ indoors.",
            ]
        ),
        "maps-lab": ImplementationGuide(
            snippet: #"""
            import MapKit

            /// Geocodes an address, routes to it and fetches a Look Around scene (iOS 26 MapKit).
            func routeAndLookAround(to address: String, from origin: MKMapItem) async throws -> (route: MKRoute?, scene: MKLookAroundScene?) {
                guard let request = MKGeocodingRequest(addressString: address),
                      let destination = try await request.mapItems.first else { return (nil, nil) }

                let directions = MKDirections.Request()
                directions.source = origin
                directions.destination = destination
                directions.transportType = .walking
                let route = try await MKDirections(request: directions).calculate().routes.first
                if let route {
                    print(route.distance, "m,", route.expectedTravelTime / 60, "min")
                }

                let scene = try await MKLookAroundSceneRequest(mapItem: destination).scene
                return (route, scene)
            }
            """#,
            infoPlist: [
                .init(key: "NSLocationWhenInUseUsageDescription", value: "Shows your position and routes from where you are."),
            ],
            notes: [
                "MKGeocodingRequest and MKReverseGeocodingRequest replace CLGeocoder on iOS 26.",
                "Look Around is not available everywhere; a nil scene is a normal result. Show it with LookAroundPreview in SwiftUI.",
                "The location key is only needed when you use the user's position (MKMapItem.forCurrentLocation() needs none).",
            ]
        ),
    ]
}
