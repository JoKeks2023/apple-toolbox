import SwiftUI

/// Run views for the Health category.
struct HealthRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "healthkit-status": HealthKitRunView()
        default: UnroutedExperimentView()
        }
    }
}
