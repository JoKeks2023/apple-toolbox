import SwiftUI

/// Run views for the Sensors category.
struct SensorsRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "core-motion": CoreMotionRunView()
        default: UnroutedExperimentView()
        }
    }
}
