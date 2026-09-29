import SwiftUI

/// Run views for the Home category.
struct HomeRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "homekit-discovery": HomeKitRunView()
        case "matter-status": MatterSetupRunView()
        default: UnroutedExperimentView()
        }
    }
}
