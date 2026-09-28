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
    @Published private(set) var output = "HomeKit discovery is ready. Refresh to request access."
    @Published private(set) var status: ExperimentStatus = .permissionRequired
    @Published private(set) var homes: [HomeSummary] = []
    #if canImport(HomeKit) && !os(macOS)
    /// Created on the first refresh: instantiating HMHomeManager triggers the HomeKit privacy prompt.
    private var manager: HMHomeManager?
    #endif

    override init() {
        super.init()
        #if !canImport(HomeKit) || os(macOS)
        status = .platformUnsupported
        #endif
    }

    func refresh() {
        #if canImport(HomeKit) && !os(macOS)
        guard let manager else {
            let manager = HMHomeManager()
            manager.delegate = self
            self.manager = manager
            output = "Waiting for HomeKit to load homes…"
            return
        }
        apply(manager)
        #else
        output = "HomeKit is not available on this platform."
        #endif
    }

    #if canImport(HomeKit) && !os(macOS)
    private func apply(_ manager: HMHomeManager) {
        let authorization = manager.authorizationStatus
        guard authorization.contains(.authorized) else {
            homes = []
            if authorization.contains(.restricted) {
                status = .permissionDenied
                output = "HomeKit access is restricted on this device."
            } else if authorization.contains(.determined) {
                status = .permissionDenied
                output = "HomeKit access was denied. Allow it in Settings › Privacy & Security › HomeKit."
            } else {
                status = .permissionRequired
                output = "HomeKit access has not been decided yet."
            }
            return
        }
        homes = manager.homes.map { HomeSummary(name: $0.name, rooms: $0.rooms.count, accessories: $0.accessories.count) }
        status = .available
        output = homes.isEmpty ? "HomeKit access granted, but no homes are set up." : "Found \(homes.count) home(s)."
    }
    #endif
}

#if canImport(HomeKit) && !os(macOS)
extension HomeExperimentService: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) { apply(manager) }
    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) { apply(manager) }
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
