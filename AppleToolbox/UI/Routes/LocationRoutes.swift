import SwiftUI

/// Run views for the Location category.
struct LocationRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "core-location": CoreLocationRunView()
        case "ibeacon-ranging": BeaconRangingRunView()
        case "location-dashboard": LocationDashboardRunView()
        default: UnroutedExperimentView()
        }
    }
}
