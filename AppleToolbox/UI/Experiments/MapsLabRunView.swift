import SwiftUI
#if canImport(MapKit)
import MapKit
#endif

#if canImport(MapKit)
/// Map appearance chosen in the Maps lab, turned into a SwiftUI `MapStyle`.
struct MapsLabAppearance {
    enum Style: String, CaseIterable, Identifiable {
        case standard = "Standard", imagery = "Satellite imagery", hybrid = "Hybrid"
        var id: String { rawValue }
    }

    enum Elevation: String, CaseIterable, Identifiable {
        case automatic = "Automatic", realistic = "Realistic (3D terrain and buildings)", flat = "Flat"
        var id: String { rawValue }
        var value: MapStyle.Elevation {
            switch self {
            case .automatic: .automatic
            case .realistic: .realistic
            case .flat: .flat
            }
        }
    }

    enum PointsOfInterest: String, CaseIterable, Identifiable {
        case all = "All", none = "None", food = "Food & drink", transport = "Transport & parking", leisure = "Culture & leisure"
        var id: String { rawValue }
        var value: PointOfInterestCategories {
            switch self {
            case .all: .all
            case .none: .excludingAll
            case .food: .including([.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket])
            case .transport: .including([.publicTransport, .parking, .airport, .gasStation, .evCharger, .carRental])
            case .leisure: .including([.museum, .theater, .movieTheater, .library, .park, .nationalPark, .stadium, .zoo, .aquarium])
            }
        }
    }

    enum Emphasis: String, CaseIterable, Identifiable {
        case automatic = "Automatic", muted = "Muted"
        var id: String { rawValue }
    }

    enum Pitch: String, CaseIterable, Identifiable {
        case topDown = "Top-down (0°)", tilted = "Tilted (45°)", steep = "Steep 3D (70°)"
        var id: String { rawValue }
        var degrees: Double {
            switch self {
            case .topDown: 0
            case .tilted: 45
            case .steep: 70
            }
        }
    }

    var style = Style.standard
    var elevation = Elevation.realistic
    var pointsOfInterest = PointsOfInterest.all
    var emphasis = Emphasis.automatic
    var showsTraffic = false
    var pitch = Pitch.topDown

    var mapStyle: MapStyle {
        switch style {
        case .standard: .standard(elevation: elevation.value, emphasis: emphasis == .muted ? .muted : .automatic, pointsOfInterest: pointsOfInterest.value, showsTraffic: showsTraffic)
        case .imagery: .imagery(elevation: elevation.value)
        case .hybrid: .hybrid(elevation: elevation.value, pointsOfInterest: pointsOfInterest.value, showsTraffic: showsTraffic)
        }
    }
}

struct MapsLabRunView: View {
    @StateObject private var lab = MapsLabService()
    @State private var appearance = MapsLabAppearance()
    @State private var position = MapCameraPosition.automatic
    @State private var camera: MapCamera?

    var body: some View {
        TextField("Address or place to geocode", text: $lab.addressQuery)
            .onSubmit(lab.geocode)
        HStack {
            Button("Geocode", systemImage: "magnifyingglass", action: lab.geocode)
                .buttonStyle(.borderedProminent)
            Button("Reverse Geocode Map Center", systemImage: "scope", action: lab.reverseGeocodeMapCenter)
                .buttonStyle(.bordered)
        }
        .disabled(lab.isBusy)
        if lab.isBusy { ProgressView("Waiting for MapKit…") }
        OutputView(text: lab.output, isError: lab.isError)
        Section("Map") {
            mapView
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            #if os(tvOS)
            Text("Apple TV cannot tap map positions; reverse geocode the map center instead.").font(.caption).foregroundStyle(.secondary)
            #else
            Text("Tap the map to reverse geocode that spot · orange circle: 250 m overlay around the selected place · blue: routes").font(.caption).foregroundStyle(.secondary)
            #endif
            LabeledContent("Location access", value: lab.authorization)
            if lab.canRequestLocation {
                Button("Allow Location for Your Position", systemImage: "location", action: lab.requestLocationPermission)
            }
        }
        MapsLabAppearanceView(appearance: $appearance)
            .onChange(of: appearance.pitch) { _, pitch in applyPitch(pitch) }
        MapsLabPlacesView(lab: lab)
        MapsLabRouteView(lab: lab)
        MapsLabLookAroundView(lab: lab)
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                ForEach(lab.places) { place in
                    Marker(place.name, systemImage: place.kind == .geocoded ? "mappin" : "hand.point.up.left", coordinate: place.coordinate)
                        .tint(place.id == lab.selectedPlaceID ? .red : place.kind == .geocoded ? .orange : .purple)
                }
                if let pinned = lab.pinnedCoordinate {
                    Annotation("Tapped", coordinate: pinned) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.purple).background(.white, in: Circle())
                    }
                }
                if let selected = lab.selectedPlace {
                    MapCircle(center: selected.coordinate, radius: 250)
                        .foregroundStyle(.orange.opacity(0.12))
                        .stroke(.orange, lineWidth: 1)
                }
                ForEach(lab.routes) { route in
                    MapPolyline(route.route)
                        .stroke(route.id == lab.selectedRouteID ? Color.blue : Color.gray.opacity(0.7), lineWidth: route.id == lab.selectedRouteID ? 6 : 4)
                }
            }
            .mapStyle(appearance.mapStyle)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                lab.visibleRegion = context.region
                camera = context.camera
            }
            .onChange(of: lab.focusID) { _, _ in
                guard let rect = lab.focusRect else { return }
                let padding = max(rect.width, rect.height, 2_000) * 0.25
                withAnimation { position = .rect(rect.insetBy(dx: -padding, dy: -padding)) }
            }
            #if !os(tvOS)
            .onTapGesture { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                lab.reverseGeocode(coordinate)
            }
            #endif
        }
    }

    private func applyPitch(_ pitch: MapsLabAppearance.Pitch) {
        let center = lab.selectedPlace?.coordinate ?? camera?.centerCoordinate ?? lab.visibleRegion?.center
        guard let center else { return }
        withAnimation {
            position = .camera(MapCamera(centerCoordinate: center, distance: camera?.distance ?? 1_500, heading: camera?.heading ?? 0, pitch: pitch.degrees))
        }
    }
}

private struct MapsLabAppearanceView: View {
    @Binding var appearance: MapsLabAppearance

    var body: some View {
        Section("Map style") {
            Picker("Style", selection: $appearance.style) {
                ForEach(MapsLabAppearance.Style.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Elevation", selection: $appearance.elevation) {
                ForEach(MapsLabAppearance.Elevation.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Camera", selection: $appearance.pitch) {
                ForEach(MapsLabAppearance.Pitch.allCases) { Text($0.rawValue).tag($0) }
            }
            if appearance.style != .imagery {
                Picker("Points of interest", selection: $appearance.pointsOfInterest) {
                    ForEach(MapsLabAppearance.PointsOfInterest.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Traffic", isOn: $appearance.showsTraffic)
            }
            if appearance.style == .standard {
                Picker("Emphasis", selection: $appearance.emphasis) {
                    ForEach(MapsLabAppearance.Emphasis.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Text("Realistic elevation shows 3D terrain and buildings where Apple has 3D data; tilt the camera to see it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MapsLabPlacesView: View {
    @ObservedObject var lab: MapsLabService

    var body: some View {
        Section("Places (\(lab.places.count))") {
            if lab.places.isEmpty {
                Text("Geocoding and reverse-geocoding results appear here with the fields MKMapItem exposes: address representations, time zone and point-of-interest category.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Selected place", selection: Binding(get: { lab.selectedPlaceID }, set: { lab.select($0) })) {
                    Text("None").tag(MapsLabPlace.ID?.none)
                    ForEach(lab.places) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            ForEach(lab.places) { place in
                VStack(alignment: .leading, spacing: 3) {
                    Label(place.name, systemImage: place.id == lab.selectedPlaceID ? "checkmark.circle.fill" : "mappin.and.ellipse")
                        .font(.headline)
                    if let address = place.fullAddress { Text(address).font(.subheadline) }
                    Text([place.kind.rawValue, place.cityWithContext, place.region, place.category, place.timeZone].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(place.coordinateText).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            if !lab.places.isEmpty {
                Button("Clear Places", systemImage: "trash", role: .destructive, action: lab.clearPlaces)
            }
        }
    }
}

private struct MapsLabRouteView: View {
    @ObservedObject var lab: MapsLabService

    var body: some View {
        Section("Route & ETA") {
            Picker("From", selection: $lab.originID) {
                Text("My location").tag(MapsLabPlace.ID?.none)
                ForEach(lab.places) { Text($0.name).tag(Optional($0.id)) }
            }
            LabeledContent("To", value: lab.selectedPlace?.name ?? "Select a place above")
            Picker("Transport", selection: $lab.transport) {
                ForEach(MapsTransport.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            if lab.transport.providesRouteGeometry {
                Toggle("Alternate routes", isOn: $lab.requestsAlternateRoutes)
            } else {
                Text("MapKit supports transit only for ETA calculations: apps get travel time, departure and arrival, but no transit route line or steps. Apple Maps shows the full transit route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(lab.transport.providesRouteGeometry ? "Calculate Route" : "Calculate ETA", systemImage: "arrow.triangle.turn.up.right.diamond", action: lab.calculateRoute)
                    .buttonStyle(.borderedProminent)
                    .disabled(lab.selectedPlace == nil || lab.isBusy)
                #if !os(tvOS)
                Button("Open in Apple Maps", systemImage: "map", action: lab.openInMaps)
                    .buttonStyle(.bordered)
                    .disabled(lab.selectedPlace == nil)
                #endif
            }
            if !lab.routes.isEmpty {
                Picker("Highlighted route", selection: $lab.selectedRouteID) {
                    ForEach(lab.routes) { Text($0.route.name.isEmpty ? "Route \($0.id + 1)" : $0.route.name).tag($0.id) }
                }
            }
            ForEach(lab.routes) { route in
                VStack(alignment: .leading, spacing: 3) {
                    Label(route.route.name.isEmpty ? "Route \(route.id + 1)" : route.route.name, systemImage: route.id == lab.selectedRouteID ? "checkmark.circle.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.headline)
                    Text(route.summary).font(.subheadline)
                    Text(route.flags).font(.caption).foregroundStyle(.secondary)
                    ForEach(route.route.advisoryNotices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    #if os(tvOS)
                    RouteStepsView(route: route.route)
                    #else
                    DisclosureGroup("Steps") { RouteStepsView(route: route.route) }
                        .font(.caption)
                    #endif
                }
            }
            if let eta = lab.eta {
                LabeledContent("Travel time", value: MapsLabText.travelTime(eta.travelTime))
                LabeledContent("Distance", value: MapsLabText.distance(eta.distance))
                LabeledContent("Departure", value: eta.departure.formatted(date: .omitted, time: .shortened))
                LabeledContent("Arrival", value: eta.arrival.formatted(date: .omitted, time: .shortened))
            }
        }
    }
}

private struct RouteStepsView: View {
    let route: MKRoute

    var body: some View {
        ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
            if !step.instructions.isEmpty {
                LabeledContent(step.instructions, value: MapsLabText.distance(step.distance)).font(.caption)
            }
        }
    }
}

private struct MapsLabLookAroundView: View {
    @ObservedObject var lab: MapsLabService

    var body: some View {
        Section("Look Around") {
            #if os(tvOS)
            Text("Look Around is not available on Apple TV: MKLookAroundSceneRequest and LookAroundPreview exist only on iOS, iPadOS and macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            Text(lab.lookAroundStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let scene = lab.lookAroundScene {
                LookAroundPreview(initialScene: scene)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .id(lab.lookAroundID)
            }
            #endif
        }
    }
}
#endif
