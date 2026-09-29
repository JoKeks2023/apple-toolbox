import SwiftUI

/// Run views for the Connectivity category.
struct ConnectivityRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "core-bluetooth": CoreBluetoothRunView()
        case "multipeer-connectivity": MultipeerRunView()
        case "continuity": WatchConnectivityRunView()
        case "nearby-interaction": NearbyInteractionRunView()
        default: UnroutedExperimentView()
        }
    }
}
