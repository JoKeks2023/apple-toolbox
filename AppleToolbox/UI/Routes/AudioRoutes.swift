import SwiftUI

/// Run views for the Audio category.
struct AudioRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "audio-input": AudioAnalyzerRunView()
        case "sound-analysis": SoundAnalysisRunView()
        case "media-playback": MediaPlaybackRunView()
        case "musickit": MusicKitRunView()
        case "shazamkit": ShazamKitRunView()
        default: UnroutedExperimentView()
        }
    }
}
