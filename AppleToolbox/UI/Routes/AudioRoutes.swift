import SwiftUI

/// Run views for the Audio category.
struct AudioRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "audio-input": AudioInputRunView()
        case "sound-analysis": SoundAnalysisRunView()
        case "musickit": MusicKitRunView()
        case "shazamkit": ShazamKitRunView()
        default: UnroutedExperimentView()
        }
    }
}
