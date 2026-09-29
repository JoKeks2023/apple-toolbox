import Foundation
import Combine

#if canImport(MapKit) && !os(watchOS)
import MapKit
#endif

struct MapSearchResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let coordinate: String
    let address: String
}

@MainActor
final class MapExperimentService: ObservableObject {
    @Published private(set) var output = "MapKit search is ready."
    @Published private(set) var isSearching = false
    @Published var query = "Apple Store"
    @Published private(set) var results: [MapSearchResult] = []

    func search() {
        #if canImport(MapKit) && !os(watchOS)
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { @Sendable [weak self] response, error in
            Task { @MainActor in
                self?.isSearching = false
                if let error { self?.output = "MapKit error: \(error.localizedDescription)"; return }
                let items = response?.mapItems.prefix(5) ?? []
                self?.results = items.map { item in
                    // MKMapItem.placemark is deprecated since iOS/macOS/tvOS 26; location and address replace it.
                    let coordinate = item.location.coordinate
                    let address = item.address?.shortAddress ?? item.address?.fullAddress ?? ""
                    return MapSearchResult(name: item.name ?? "Unnamed", coordinate: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude), address: address)
                }
                self?.output = items.isEmpty ? "No results." : "Found \(items.count) result(s) for \(self?.query ?? "your query")."
            }
        }
        #else
        output = "MapKit search is not available on this platform."
        #endif
    }
}
