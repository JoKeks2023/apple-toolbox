import SwiftUI

/// Run views for the Maps category.
struct MapsRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "mapkit-search": MapKitSearchRunView()
        case "indoor-imdf": IndoorIMDFRunView()
        case "indoor-survey": IndoorSurveyRunView()
        default: UnroutedExperimentView()
        }
    }
}
