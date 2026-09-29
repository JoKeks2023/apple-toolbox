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
        let permission: PermissionState = authorization.contains(.authorized) ? .granted
            : authorization.contains(.restricted) ? .restricted
            : authorization.contains(.determined) ? .denied : .notDetermined
        PermissionProbe.remember(permission, for: .homeKit)
        PermissionCenter.shared.invalidate()
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

/// Starts Apple Home's own accessory setup UI, which commissions Matter accessories into a home. The app needs the
/// HomeKit entitlement but no home-data authorization. No setup payload is passed, so the
/// com.apple.developer.matter.allow-setup-payload entitlement is not required.
@MainActor
final class MatterSetupExperimentService: ObservableObject {
    @Published private(set) var output = "Starts Apple Home's setup flow to add a Matter accessory to one of your homes."
    @Published private(set) var isRunning = false
    @Published private(set) var isError = false
    @Published private(set) var homeIdentifier: String?
    @Published private(set) var accessoryIdentifiers: [String] = []
    #if canImport(HomeKit) && os(iOS)
    private var manager: HMAccessorySetupManager?
    #endif

    func startSetup() {
        #if canImport(HomeKit) && os(iOS)
        let manager = HMAccessorySetupManager()
        self.manager = manager
        isRunning = true
        isError = false
        output = "Apple Home setup is open. Scan the accessory's setup code and follow the system steps."
        Task {
            defer { isRunning = false; self.manager = nil }
            do {
                let result = try await manager.performAccessorySetup(using: HMAccessorySetupRequest())
                let home = result.homeUniqueIdentifier.uuidString
                homeIdentifier = home
                accessoryIdentifiers = result.accessoryUniqueIdentifiers.map(\.uuidString)
                output = "Setup finished: \(accessoryIdentifiers.count) accessory(ies) added to home \(home).\nHomeKit Discovery lists them by name once HomeKit access is granted."
            } catch let error as HMError where error.code == .operationCancelled {
                isError = true
                output = "Setup was cancelled before an accessory was added."
            } catch {
                let nsError = error as NSError
                isError = true
                output = "Setup failed: \(error.localizedDescription)\n\(nsError.domain) code \(nsError.code)"
            }
        }
        #else
        output = "Apple Home accessory setup (HMAccessorySetupManager) is not available on this platform."
        #endif
    }
}

extension ExperimentAvailability {
    /// Apple Home's setup UI needs no home-data authorization, so the HomeKit permission does not gate it.
    static func matterSetup() -> ExperimentStatus {
        #if canImport(HomeKit) && os(iOS)
        if #available(iOS 27.0, *) { return HMAccessorySetupManager.isSupported ? .available : .unavailable }
        return .available
        #else
        return .platformUnsupported
        #endif
    }
}
