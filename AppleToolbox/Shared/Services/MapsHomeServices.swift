import Foundation
import Combine

#if canImport(MapKit) && !os(watchOS)
import MapKit
#endif

#if canImport(HomeKit) && !os(macOS)
import HomeKit
#endif

@MainActor
final class MapExperimentService: ObservableObject {
    @Published private(set) var output = "MapKit search is ready."
    @Published private(set) var isSearching = false

    func search() {
        #if canImport(MapKit) && !os(watchOS)
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Apple Store"
        MKLocalSearch(request: request).start { [weak self] response, error in
            Task { @MainActor in
                self?.isSearching = false
                if let error { self?.output = "MapKit error: \(error.localizedDescription)"; return }
                let items = response?.mapItems.prefix(5) ?? []
                self?.output = items.isEmpty ? "No results." : items.map { item in
                    let coordinate = item.placemark.coordinate
                    return "\(item.name ?? "Unnamed") · \(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))"
                }.joined(separator: "\n")
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
        status = .available
        output = homes.isEmpty ? "No homes available. HomeKit permission may still be pending." : homes.map { "\($0.name) · \($0.rooms.count) room(s) · \($0.accessories.count) accessory(ies)" }.joined(separator: "\n")
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
