import SwiftUI

/// Run views for the Developer category.
struct DeveloperRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "capability-explorer": DeviceScannerRunView()
        case "developer-tools": DeveloperToolsLabRunView()
        case "diagnostics": DiagnosticsRunView()
        default: UnroutedExperimentView()
        }
    }
}
