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

struct HomeSummary: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let rooms: Int
    let accessories: Int
}

#if canImport(HomeKit) && !os(macOS)
import HomeKit
#endif

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
        MKLocalSearch(request: request).start { [weak self] response, error in
            Task { @MainActor in
                self?.isSearching = false
                if let error { self?.output = "MapKit error: \(error.localizedDescription)"; return }
                let items = response?.mapItems.prefix(5) ?? []
                self?.results = items.map { item in
                    let coordinate = item.placemark.coordinate
                    let address = [item.placemark.thoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
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

@MainActor
final class HomeExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "HomeKit discovery is ready."
    @Published private(set) var status: ExperimentStatus = .permissionRequired
    @Published private(set) var homes: [HomeSummary] = []
    #if canImport(HomeKit) && !os(macOS)
    private var manager: HMHomeManager!
    #endif

    override init() {
        super.init()
        #if canImport(HomeKit) && !os(macOS)
        manager = HMHomeManager()
        manager.delegate = self
        #else
        status = .platformUnsupported
        #endif
    }

    func refresh() {
        #if canImport(HomeKit) && !os(macOS)
        let homes = manager.homes
        self.homes = homes.map { HomeSummary(name: $0.name, rooms: $0.rooms.count, accessories: $0.accessories.count) }
        status = .available
        output = homes.isEmpty ? "No homes available. HomeKit permission may still be pending." : "Found \(homes.count) home(s)."
        #else
        output = "HomeKit is not available on this platform."
        #endif
    }
}

#if canImport(HomeKit) && !os(macOS)
extension HomeExperimentService: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { refresh() }
    func homeManager(_ manager: HMHomeManager, didEncounterError error: Error) { status = .unavailable; output = "HomeKit error: \(error.localizedDescription)" }
}
#endif

struct MatterExperimentService {
    static func statusText() -> String {
        #if canImport(Matter)
        return "Matter framework is present. Commissioning requires a setup payload, supported accessory, and Apple-approved flow."
        #else
        return "Matter framework is not available in this SDK/platform target."
        #endif
    }
}
