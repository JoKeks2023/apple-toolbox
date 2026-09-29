import SwiftUI

/// Run views for the Camera category.
struct CameraRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "camera-lab": CameraLabRunView()
        case "camera-vision": CameraVisionRunView()
        default: UnroutedExperimentView()
        }
    }
}
