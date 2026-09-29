import SwiftUI

/// Run views for the Home category.
struct HomeRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "homekit-discovery": HomeInspectorRunView(experiment: experiment)
        case "matter-status": MatterSetupRunView()
        case "homekit-accessory-browser": HomeAccessoryBrowserRunView()
        default: UnroutedExperimentView()
        }
    }
}
