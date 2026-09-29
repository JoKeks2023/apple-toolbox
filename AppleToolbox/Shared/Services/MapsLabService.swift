import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit) && !os(watchOS)
import MapKit
#endif

/// Transport modes offered by MKDirections.
nonisolated enum MapsTransport: String, CaseIterable, Identifiable, Sendable {
    case automobile, walking, transit, cycling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automobile: "Driving"
        case .walking: "Walking"
        case .transit: "Transit"
        case .cycling: "Cycling"
        }
    }

    var symbol: String {
        switch self {
        case .automobile: "car"
        case .walking: "figure.walk"
        case .transit: "tram"
        case .cycling: "bicycle"
        }
    }

    /// MapKit returns route geometry and steps for these modes; transit is supported for ETA calculations only.
    var providesRouteGeometry: Bool { self != .transit }
}

nonisolated enum MapsLabText {
    /// "12 min", "1 h 05 min"
    static func travelTime(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(max(minutes, seconds > 0 ? 1 : 0)) min" }
        return "\(minutes / 60) h " + String(format: "%02d min", minutes % 60)
    }

    static func distance(_ meters: Double) -> String {
        meters >= 1_000 ? (meters / 1_000).formatted(.number.precision(.fractionLength(1))) + " km" : "\(Int(meters.rounded())) m"
    }

    /// "MKPOICategoryPublicTransport" → "Public Transport"
    static func category(_ rawValue: String) -> String {
        let name = rawValue.hasPrefix("MKPOICategory") ? String(rawValue.dropFirst("MKPOICategory".count)) : rawValue
        let characters = Array(name)
        var words = ""
        for (index, character) in characters.enumerated() {
            if index > 0, character.isUppercase {
                let previous = characters[index - 1]
                let nextIsLowercase = index + 1 < characters.count && characters[index + 1].isLowercase
                if previous.isLowercase || (previous.isUppercase && nextIsLowercase) { words.append(" ") }
            }
            words.append(character)
        }
        return words
    }

    static func coordinate(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}

#if canImport(MapKit) && !os(watchOS)
extension MapsTransport {
    nonisolated var directionsType: MKDirectionsTransportType {
        switch self {
        case .automobile: .automobile
        case .walking: .walking
        case .transit: .transit
        case .cycling: .cycling
        }
    }

    #if !os(tvOS)
    nonisolated var launchMode: String {
        switch self {
        case .automobile: MKLaunchOptionsDirectionsModeDriving
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .cycling: MKLaunchOptionsDirectionsModeCycling
        }
    }
    #endif
}

/// A place returned by geocoding or reverse geocoding, read through the iOS 26 MKMapItem address API.
struct MapsLabPlace: Identifiable, Equatable {
    enum Kind: String { case geocoded = "Geocoded", reverseGeocoded = "Reverse geocoded" }

    let id = UUID()
    let kind: Kind
    let item: MKMapItem
    let name: String
    let latitude: Double
    let longitude: Double
    let fullAddress: String?
    let cityWithContext: String?
    let region: String?
    let timeZone: String?
    let category: String?

    init(item: MKMapItem, kind: Kind) {
        self.kind = kind
        self.item = item
        name = item.name ?? item.address?.shortAddress ?? "Unnamed place"
        latitude = item.location.coordinate.latitude
        longitude = item.location.coordinate.longitude
        fullAddress = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) ?? item.address?.fullAddress
        cityWithContext = item.addressRepresentations?.cityWithContext
        region = item.addressRepresentations?.regionName
        timeZone = item.timeZone?.identifier
        category = item.pointOfInterestCategory.map { MapsLabText.category($0.rawValue) }
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var coordinateText: String { MapsLabText.coordinate(latitude: latitude, longitude: longitude) }
}

struct MapsLabRoute: Identifiable {
    let id: Int
    let route: MKRoute

    var summary: String {
        "\(MapsLabText.distance(route.distance)) · \(MapsLabText.travelTime(route.expectedTravelTime)) · arrive \(Date().addingTimeInterval(route.expectedTravelTime).formatted(date: .omitted, time: .shortened))"
    }

    var flags: String {
        var flags: [String] = []
        if route.hasTolls { flags.append("tolls") }
        if route.hasHighways { flags.append("highways") }
        flags.append("\(route.steps.count) steps")
        return flags.joined(separator: " · ")
    }
}

struct MapsLabETA {
    let transport: MapsTransport
    let travelTime: TimeInterval
    let distance: Double
    let departure: Date
    let arrival: Date
}

/// Geocoding, routing and Look Around with MapKit's current (iOS 26) request APIs.
@MainActor
final class MapsLabService: NSObject, ObservableObject {
    @Published var addressQuery = "Apple Park Visitor Center, Cupertino"
    @Published private(set) var places: [MapsLabPlace] = []
    @Published var selectedPlaceID: MapsLabPlace.ID?
    /// nil routes from the current location.
    @Published var originID: MapsLabPlace.ID?
    @Published var transport = MapsTransport.automobile
    @Published var requestsAlternateRoutes = true
    @Published private(set) var routes: [MapsLabRoute] = []
    @Published var selectedRouteID = 0
    @Published private(set) var eta: MapsLabETA?
    @Published private(set) var pinnedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var isBusy = false
    @Published private(set) var authorization = "Not determined"
    @Published private(set) var isError = false
    @Published private(set) var output = "Geocode an address, tap the map to reverse geocode, then route between places."
    /// Changes whenever the map should frame `focusRect`.
    @Published private(set) var focusID = UUID()
    private(set) var focusRect: MKMapRect?
    #if !os(tvOS)
    @Published private(set) var lookAroundScene: MKLookAroundScene?
    @Published private(set) var lookAroundStatus = "Select a place to request Look Around imagery."
    @Published private(set) var lookAroundID = UUID()
    #endif

    /// Last visible map region, used to bias geocoding and as the reverse-geocoding fallback.
    var visibleRegion: MKCoordinateRegion?
    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    #endif

    override init() {
        super.init()
        #if canImport(CoreLocation)
        manager.delegate = self
        updateAuthorization(manager.authorizationStatus)
        #endif
    }

    var selectedPlace: MapsLabPlace? { places.first { $0.id == selectedPlaceID } }
    var canRequestLocation: Bool { authorization == "Not determined" }

    func requestLocationPermission() {
        #if canImport(CoreLocation)
        manager.requestWhenInUseAuthorization()
        #endif
    }

    // MARK: Geocoding

    func geocode() {
        let query = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isBusy else { return }
        guard let request = MKGeocodingRequest(addressString: query) else {
            report("MKGeocodingRequest rejected the address string.", isError: true)
            return
        }
        if let visibleRegion { request.region = visibleRegion }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let items = try await request.mapItems
                let results = items.map { MapsLabPlace(item: $0, kind: .geocoded) }
                replacePlaces(of: .geocoded, with: results)
                if let first = results.first { select(first.id) }
                focus(on: results.map(\.coordinate))
                report(results.isEmpty ? "MKGeocodingRequest found no match for “\(query)”." : "MKGeocodingRequest returned \(results.count) map item(s) for “\(query)”.")
            } catch {
                report("Geocoding failed: \(Self.describe(error))", isError: true)
            }
        }
    }

    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        guard !isBusy else { return }
        pinnedCoordinate = coordinate
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) else {
            report("MKReverseGeocodingRequest rejected the coordinate.", isError: true)
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let items = try await request.mapItems
                let results = items.map { MapsLabPlace(item: $0, kind: .reverseGeocoded) }
                replacePlaces(of: .reverseGeocoded, with: results)
                if let first = results.first { select(first.id) }
                let location = MapsLabText.coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                report(results.first.map { "MKReverseGeocodingRequest at \(location): \($0.fullAddress ?? $0.name)" } ?? "MKReverseGeocodingRequest found no address at \(location).")
            } catch {
                report("Reverse geocoding failed: \(Self.describe(error))", isError: true)
            }
        }
    }

    func reverseGeocodeMapCenter() {
        guard let center = visibleRegion?.center else {
            report("Move the map once so its center is known, then try again.", isError: true)
            return
        }
        reverseGeocode(center)
    }

    func select(_ id: MapsLabPlace.ID?) {
        selectedPlaceID = id
        routes = []
        eta = nil
        #if !os(tvOS)
        loadLookAround()
        #endif
    }

    func clearPlaces() {
        places = []
        pinnedCoordinate = nil
        originID = nil
        select(nil)
        report("Cleared all places and routes.")
    }

    private func replacePlaces(of kind: MapsLabPlace.Kind, with results: [MapsLabPlace]) {
        let removed = Set(places.filter { $0.kind == kind }.map(\.id))
        if let originID, removed.contains(originID) { self.originID = nil }
        places = places.filter { $0.kind != kind } + results
    }

    // MARK: Routing

    func calculateRoute() {
        guard !isBusy else { return }
        guard let destination = selectedPlace else {
            report("Select a destination place first.", isError: true)
            return
        }
        let origin = places.first { $0.id == originID }
        if origin == nil, !isLocationAuthorized {
            requestLocationPermission()
            report("Routing from your location needs location access. Allow it, or pick a geocoded place as the origin.", isError: true)
            return
        }
        let request = MKDirections.Request()
        request.source = origin?.item ?? MKMapItem.forCurrentLocation()
        request.destination = destination.item
        request.transportType = transport.directionsType
        request.requestsAlternateRoutes = requestsAlternateRoutes
        let directions = MKDirections(request: request)
        let transport = transport
        let from = origin?.name ?? "your location"
        isBusy = true
        routes = []
        eta = nil
        Task {
            defer { isBusy = false }
            do {
                if transport.providesRouteGeometry {
                    let response = try await directions.calculate()
                    routes = response.routes.enumerated().map { MapsLabRoute(id: $0.offset, route: $0.element) }
                    selectedRouteID = 0
                    if let first = routes.first {
                        focusRect = response.routes.dropFirst().reduce(first.route.polyline.boundingMapRect) { $0.union($1.polyline.boundingMapRect) }
                        focusID = UUID()
                    }
                    report("MKDirections returned \(routes.count) \(transport.title.lowercased()) route(s) from \(from) to \(destination.name).")
                } else {
                    let response = try await directions.calculateETA()
                    eta = MapsLabETA(transport: transport, travelTime: response.expectedTravelTime, distance: response.distance,
                                     departure: response.expectedDepartureDate, arrival: response.expectedArrivalDate)
                    report("MKDirections.calculateETA(): transit from \(from) to \(destination.name) takes \(MapsLabText.travelTime(response.expectedTravelTime)).\nMapKit supports transit only for ETAs; it returns no transit route geometry or steps to apps.")
                }
            } catch {
                report("Directions failed: \(Self.describe(error))", isError: true)
            }
        }
    }

    #if !os(tvOS)
    func openInMaps() {
        guard let destination = selectedPlace else { return }
        let origin = places.first { $0.id == originID }?.item ?? MKMapItem.forCurrentLocation()
        let opened = MKMapItem.openMaps(with: [origin, destination.item], launchOptions: [MKLaunchOptionsDirectionsModeKey: transport.launchMode])
        report(opened ? "Handed the \(transport.title.lowercased()) route to Apple Maps." : "Apple Maps could not be opened.", isError: !opened)
    }
    #endif

    // MARK: Look Around

    #if !os(tvOS)
    private func loadLookAround() {
        lookAroundScene = nil
        lookAroundID = UUID()
        guard let place = selectedPlace else {
            lookAroundStatus = "Select a place to request Look Around imagery."
            return
        }
        lookAroundStatus = "Requesting a Look Around scene for \(place.name)…"
        let request = MKLookAroundSceneRequest(mapItem: place.item)
        let placeID = place.id
        Task {
            do {
                let scene = try await request.scene
                guard selectedPlaceID == placeID else { return }
                lookAroundScene = scene
                lookAroundID = UUID()
                lookAroundStatus = scene == nil ? "Apple has no Look Around imagery at \(place.name)." : "MKLookAroundSceneRequest returned a scene. Drag inside the preview to look around."
            } catch {
                guard selectedPlaceID == placeID else { return }
                lookAroundStatus = "Look Around request failed: \(Self.describe(error))"
            }
        }
    }
    #endif

    // MARK: Helpers

    private var isLocationAuthorized: Bool { authorization.hasPrefix("Authorized") }

    private func focus(on coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return }
        let rect = coordinates.dropFirst().reduce(MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))) {
            $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize(width: 0, height: 0)))
        }
        focusRect = rect
        focusID = UUID()
    }

    private func report(_ message: String, isError: Bool = false) {
        output = message
        self.isError = isError
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(error.localizedDescription) (\(nsError.domain) code \(nsError.code))"
        if let mapError = error as? MKError {
            switch mapError.code {
            case .directionsNotFound: text += "\nNo route exists for this transport mode between the two places, or the mode is not offered in this region."
            case .placemarkNotFound: text += "\nMapKit found no place for this input."
            case .loadingThrottled: text += "\nMapKit throttles apps that send too many requests; wait a moment."
            case .serverFailure: text += "\nThe MapKit service could not be reached; check the network connection."
            default: break
            }
        }
        return text
    }

    #if canImport(CoreLocation)
    fileprivate func updateAuthorization(_ status: CLAuthorizationStatus) {
        authorization = switch status {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Authorized · Always"
        case .authorizedWhenInUse: "Authorized · When In Use"
        @unknown default: "Unknown"
        }
    }
    #endif
}

#if canImport(CoreLocation)
extension MapsLabService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.updateAuthorization(status)
            PermissionCenter.shared.invalidate()
        }
    }
}
#endif
#endif
