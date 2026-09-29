import SwiftUI

/// Run views for the Platform category.
struct PlatformRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "metal": MetalRunView()
        case "mac-hardware": MacHardwareRunView()
        case "apple-pencil": ApplePencilRunView()
        case "pointer-keyboard": PointerKeyboardRunView()
        case "windows-displays": WindowsDisplaysRunView()
        default: UnroutedExperimentView()
        }
    }
}
