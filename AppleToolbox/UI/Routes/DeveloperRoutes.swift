import SwiftUI

/// Run views for the Developer category.
struct DeveloperRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "capability-explorer": DeviceScannerRunView()
        default: UnroutedExperimentView()
        }
    }
}
