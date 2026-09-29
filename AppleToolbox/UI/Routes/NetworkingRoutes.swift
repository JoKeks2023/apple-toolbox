import SwiftUI

/// Run views for the Networking category.
struct NetworkingRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "network-path": NetworkInspectorRunView()
        default: UnroutedExperimentView()
        }
    }
}
