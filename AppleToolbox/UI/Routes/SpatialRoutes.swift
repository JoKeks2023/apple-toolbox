import SwiftUI

/// Run views for the Spatial category.
struct SpatialRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "arkit": ARLabRunView()
        case "roomplan": RoomPlanRunView()
        default: UnroutedExperimentView()
        }
    }
}
