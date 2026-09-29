import SwiftUI

/// Run views for the Input category.
struct InputRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "game-controller": GameControllerRunView()
        default: UnroutedExperimentView()
        }
    }
}
