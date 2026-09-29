import SwiftUI

/// Run views for the AI category.
struct AIRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "natural-language": NaturalLanguageRunView()
        case "foundation-models": FoundationModelsRunView()
        case "speech": SpeechRunView()
        case "speech-analyzer": SpeechAnalyzerRunView()
        case "core-ml": CoreMLRunView()
        case "translation": TranslationRunView()
        default: UnroutedExperimentView()
        }
    }
}
